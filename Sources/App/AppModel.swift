import Foundation
import Observation
import UIKit

/// Thread-safe snapshot of the files offered by the download API (read on the server queue).
final class FilesBox: @unchecked Sendable {
  private let lock = NSLock()
  private var files: [FileDTO] = []

  func set(_ files: [FileDTO]) {
    lock.lock()
    self.files = files
    lock.unlock()
  }

  var value: [FileDTO] {
    lock.lock()
    defer { lock.unlock() }
    return files
  }
}

@MainActor
@Observable
final class AppModel {
  struct PinRequest: Identifiable, Equatable {
    let id: String
    let device: Device
    let files: [SelectedFile]
    var alias: String { device.alias }
  }

  let settings = AppSettings()
  let history = HistoryStore()
  let favorites = FavoritesStore()
  let discovery = DiscoveryService()
  let server = LocalHTTPServer()
  let identity = LocalIdentity.load()

  private(set) var deviceIdentity: DeviceIdentity
  private(set) var addresses: [String] = []
  private(set) var serverRunning = false
  private(set) var receivedFiles: [ReceivedFile] = []
  var incoming: IncomingRequest?
  var outgoing: OutgoingTransfer?
  var pinRequest: PinRequest?
  var errorMessage: String?
  /// Files staged for the next send, also filled by the Share Extension.
  var selection: [SelectedFile] = []

  var selectionBytes: Int64 { selection.reduce(0) { $0 + Int64($1.size) } }

  /// Drains the Share Extension inbox into the current selection.
  func consumeShareInbox() {
    let urls = ShareInbox.drain()
    guard !urls.isEmpty else { return }
    selection = urls.compactMap(SelectedFile.make(from:))
  }

  /// Files currently offered by the web download page.
  private let downloadBox = FilesBox()
  /// Identity snapshot the HTTP server may read from its own queue.
  private let infoBox = InfoBox(
    DeviceInfoDTO(
      alias: "LocalSend",
      version: "2.2",
      deviceModel: nil,
      deviceType: DeviceType.mobile.rawValue,
      fingerprint: "unknown",
      port: 53317,
      protocolName: "https",
      download: false
    )
  )
  private var activePeerAlias = ""
  private var started = false

  init() {
    deviceIdentity = DeviceIdentity(
      alias: settings.alias,
      fingerprint: identity.fingerprint,
      port: settings.port,
      protocolName: settings.encryption ? "https" : "http"
    )
  }

  var info: DeviceInfoDTO { deviceIdentity.infoDTO(downloadEnabled: settings.downloadEnabled) }
  var primaryAddress: String { addresses.first ?? "0.0.0.0" }

  // MARK: Lifecycle

  func start() {
    guard !started else { return }
    started = true

    refreshAddresses()
    configureServer()
    do {
      try server.start()
      serverRunning = true
    } catch {
      serverRunning = false
      errorMessage = error.localizedDescription
    }

    discovery.start(identity: identity, ownFingerprint: identity.fingerprint, interval: settings.scanInterval)
    publishDownloads()
  }

  func stop() {
    discovery.stop()
    server.stop()
    serverRunning = false
  }

  /// Re-applies settings that require restarting the listener.
  func applyNetworkSettings() {
    deviceIdentity = DeviceIdentity(
      alias: settings.alias,
      fingerprint: identity.fingerprint,
      port: settings.port,
      protocolName: settings.encryption ? "https" : "http"
    )
    server.stop()
    configureServer()
    do {
      try server.start()
      serverRunning = true
    } catch {
      serverRunning = false
      errorMessage = error.localizedDescription
    }
    publishInfo()
    publishDownloads()
  }

  func updateAlias(_ alias: String) {
    let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    settings.alias = trimmed
    deviceIdentity.alias = trimmed
    publishInfo()
  }

  func refreshIdentity() {
    refreshAddresses()
  }

  func refreshAddresses() {
    addresses = NetworkInfo.ipv4Addresses()
    deviceIdentity = DeviceIdentity(
      alias: settings.alias,
      fingerprint: identity.fingerprint,
      port: settings.port,
      protocolName: settings.encryption ? "https" : "http"
    )
    publishInfo()
  }

  private func publishInfo() {
    infoBox.set(deviceIdentity.infoDTO(downloadEnabled: settings.downloadEnabled))
  }

  private func configureServer() {
    server.identity = identity
    server.encryption = settings.encryption
    server.pin = settings.pin.isEmpty ? nil : settings.pin
    server.port = settings.port
    server.downloadProvider = settings.downloadEnabled ? { [downloadBox] in downloadBox.value } : nil
    server.identityProvider = { [infoBox] in infoBox.value }
    server.onEvent = { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
  }

  // MARK: Server events

  private func handle(_ event: ServerEvent) {
    switch event {
    case let .incoming(sessionId, peerAlias, files):
      activePeerAlias = peerAlias
      let request = IncomingRequest(id: sessionId, peerAlias: peerAlias, files: files)
      if settings.quickSave {
        accept(request)
      } else {
        incoming = request
      }

    case let .received(fileName, url):
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      let file = ReceivedFile(id: url.path, name: fileName, url: url, size: size, date: Date())
      receivedFiles.insert(file, at: 0)
      history.add(
        direction: .received,
        alias: activePeerAlias.isEmpty ? "LocalSend" : activePeerAlias,
        files: [HistoryFile(name: fileName, size: Int64(size), relativePath: fileName)]
      )
      if settings.saveToPhotos, PhotoSaver.isMedia(url) {
        Task { await PhotoSaver.save([url]) }
      }
      publishDownloads()

    case let .peerSeen(peer):
      // The peer reached us, but its protocol is unknown: resolve it the same way a scan would.
      Task { [weak self] in
        guard let self else { return }
        if let device = await DeviceProbe.info(host: peer.host, identity: self.identity) {
          self.discovery.absorb(device)
        }
      }
    }
  }

  // MARK: Receiving

  func accept(_ request: IncomingRequest) {
    server.decide(sessionId: request.id, acceptedIds: Set(request.files.map(\.id)))
    if incoming?.id == request.id { incoming = nil }
  }

  func decline(_ request: IncomingRequest) {
    server.decide(sessionId: request.id, acceptedIds: nil)
    if incoming?.id == request.id { incoming = nil }
  }

  // MARK: Sending

  func send(files: [SelectedFile], to device: Device, pin: String? = nil) {
    guard !files.isEmpty else { return }

    let transfer = OutgoingTransfer(
      id: UUID().uuidString,
      deviceAlias: device.alias,
      fileNames: files.map(\.name),
      completed: 0,
      total: files.count,
      isFinished: false,
      error: nil
    )
    outgoing = transfer

    Task { [weak self] in
      guard let self else { return }
      await self.performSend(files: files, to: device, pin: pin)
    }
  }

  private func performSend(files: [SelectedFile], to device: Device, pin: String? = nil) async {
    let sender = TransferSender(identity: identity, settings: settings)
    do {
      let outcome = try await sender.send(
        files: files,
        to: device,
        identity: deviceIdentity,
        pin: pin,
        onSession: { [weak self] sessionId in
          self?.outgoing?.sessionId = sessionId
        }
      ) { [weak self] completed, total in
        self?.outgoing?.completed = completed
        self?.outgoing?.total = total
      }
      outgoing?.completed = outcome.uploaded
      outgoing?.isFinished = true
      history.add(
        direction: .sent,
        alias: device.alias,
        files: files.map { HistoryFile(name: $0.name, size: Int64($0.size), relativePath: nil) }
      )
    } catch let TransferError.pinRequired {
      outgoing = nil
      pinRequest = PinRequest(id: device.id, device: device, files: files)
    } catch {
      outgoing?.isFinished = true
      outgoing?.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      errorMessage = outgoing?.error
    }
  }

  func submitPin(_ pin: String) {
    guard let request = pinRequest else { return }
    pinRequest = nil
    send(files: request.files, to: request.device, pin: pin)
  }

  func dismissOutgoing() {
    outgoing = nil
  }

  func cancelOutgoing() {
    guard let outgoing else { return }
    let sessionId = outgoing.sessionId
    let alias = outgoing.deviceAlias
    self.outgoing = nil
    guard let sessionId, let device = discovery.devices.first(where: { $0.alias == alias })
      ?? favorites.devices.first(where: { $0.alias == alias }).map({ $0.asDevice })
    else {
      return
    }
    let sender = TransferSender(identity: identity, settings: settings)
    Task { await sender.cancel(sessionId: sessionId, device: device) }
  }

  // MARK: Downloads

  private func publishDownloads() {
    downloadBox.set(
      receivedFiles.map {
        FileDTO(id: $0.name, fileName: $0.name, size: $0.size, fileType: "application/octet-stream")
      }
    )
  }

  // MARK: Favourites

  func addFavorite(alias: String, host: String) {
    favorites.add(alias: alias, host: host)
  }
}
