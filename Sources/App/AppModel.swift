import Foundation
import Observation
import UIKit

/// Thread-safe snapshot of our own device info, read by the HTTP server's queue.
final class InfoBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: DeviceInfoDTO

  init(value: DeviceInfoDTO) {
    self.value = value
  }

  func get() -> DeviceInfoDTO {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ newValue: DeviceInfoDTO) {
    lock.lock()
    value = newValue
    lock.unlock()
  }
}

@MainActor
@Observable
final class AppModel {
  var settings = AppSettings()
  private(set) var identity: DeviceIdentity
  private(set) var addresses: [String] = []
  private(set) var serverRunning = false
  private(set) var lastError: String?
  private(set) var receivedFiles: [ReceivedFile] = []

  let discovery = DiscoveryService()
  let server = LocalHTTPServer()
  let infoBox: InfoBox

  var outgoing: OutgoingTransfer?
  var incoming: IncomingTransfer?

  init() {
    let loaded = DeviceIdentity.load()
    identity = loaded
    infoBox = InfoBox(value: loaded.infoDTO(downloadEnabled: false))
  }

  var info: DeviceInfoDTO { infoBox.get() }

  func start() {
    addresses = NetworkInfo.ipv4Addresses()
    publishInfo()

    server.identityProvider = { [infoBox] in infoBox.get() }
    server.onSession = { [weak self] sessionId, names, peer in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.incoming = IncomingTransfer(
          id: sessionId,
          peerAlias: peer.isEmpty ? "Nearby device" : peer,
          fileNames: names,
          received: 0,
          total: names.count,
          isFinished: false
        )
      }
    }
    server.onFileReceived = { [weak self] name, url in
      MainActor.assumeIsolated {
        guard let self else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        self.receivedFiles.insert(ReceivedFile(id: url.path, name: name, url: url, size: size, date: Date()), at: 0)
        if var current = self.incoming {
          current.received += 1
          current.isFinished = current.received >= current.total
          self.incoming = current
        }
      }
    }
    server.onPeerSeen = { [weak self] dto, host in
      MainActor.assumeIsolated {
        self?.discovery.register(peer: dto, host: host)
      }
    }

    do {
      try server.start()
      serverRunning = true
    } catch {
      serverRunning = false
      lastError = error.localizedDescription
    }

    discovery.start(ownFingerprint: identity.fingerprint, interval: settings.scanInterval)
  }

  func stop() {
    server.stop()
    discovery.stop()
    serverRunning = false
  }

  func refreshIdentity() {
    addresses = NetworkInfo.ipv4Addresses()
    identity.alias = settings.alias
    publishInfo()
  }

  private func publishInfo() {
    infoBox.set(identity.infoDTO(downloadEnabled: settings.downloadEnabled))
  }

  func updateAlias(_ alias: String) {
    let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    settings.alias = trimmed
    refreshIdentity()
  }

  func send(files: [SelectedFile], to device: Device) {
    guard !files.isEmpty else { return }
    outgoing = OutgoingTransfer(
      id: UUID().uuidString,
      deviceAlias: device.alias,
      fileNames: files.map(\.name),
      completed: 0,
      total: files.count,
      isFinished: false,
      error: nil
    )
    let snapshot = identity
    let download = settings.downloadEnabled

    Task {
      do {
        _ = try await TransferSender().send(
          files: files,
          to: device,
          identity: snapshot,
          downloadEnabled: download
        ) { [weak self] completed, total in
          self?.outgoing?.completed = completed
          self?.outgoing?.total = total
        }
        outgoing?.isFinished = true
      } catch {
        outgoing?.error = error.localizedDescription
        outgoing?.isFinished = true
      }
    }
  }

  func dismissOutgoing() {
    outgoing = nil
  }

  func dismissIncoming() {
    incoming = nil
  }
}
