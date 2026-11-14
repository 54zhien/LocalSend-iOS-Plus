import Foundation
import Observation
import UIKit

/// Thread-safe snapshot of the files offered by the download API (read on the server queue).
/// Snapshot of the identity the HTTP server answers `/info` with. The server runs on its
/// own queue, so it cannot read main-actor state; AppModel writes, the server reads.
final class InfoBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: DeviceInfoDTO

  init(_ value: DeviceInfoDTO) {
    stored = value
  }

  func set(_ value: DeviceInfoDTO) {
    lock.lock()
    stored = value
    lock.unlock()
  }

  var value: DeviceInfoDTO {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}
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
  let destination = DestinationStore()
  private let announcer = Announcer()
  private var announceTask: Task<Void, Never>?
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
      alias: "LocalSend Plus",
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
  private var activePeerFingerprint = ""
  private var started = false
  private var webReceiveMode = false
  private var webSendFiles: [SelectedFile]?
  var isWebReceiving: Bool { webReceiveMode }

  init() {
    deviceIdentity = DeviceIdentity(
      alias: settings.alias,
      fingerprint: identity.fingerprint,
      deviceModel: settings.deviceModel,
      deviceType: settings.deviceType,
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

    discovery.start(identity: identity, ownFingerprint: identity.fingerprint, interval: settings.scanInterval, timeout: settings.discoveryTimeout)
    publishDownloads()
    startAnnouncing()
  }

  /// Peers on the same subnet hear this datagram and add us to their list right away.
  func announcePresence() {
    let announce = deviceIdentity.announce(downloadEnabled: settings.downloadEnabled)
    guard let payload = try? JSONEncoder().encode(announce) else { return }
    announcer.announce(
      payload,
      hosts: NetworkInfo.candidateHosts(),
      port: UInt16(settings.port)
    )
  }

  private func startAnnouncing() {
    announcePresence()
    announceTask?.cancel()
    announceTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard let self, !Task.isCancelled else { return }
        self.announcePresence()
      }
    }
  }

  func stop() {
    announceTask?.cancel()
    discovery.stop()
    server.stop()
    serverRunning = false
    started = false
  }

  /// Re-applies settings that require restarting the listener.
  func applyNetworkSettings() {
    let encrypted = settings.encryption && !webReceiveMode && webSendFiles == nil
    deviceIdentity = DeviceIdentity(
      alias: settings.alias,
      fingerprint: identity.fingerprint,
      deviceModel: settings.deviceModel,
      deviceType: settings.deviceType,
      port: settings.port,
      protocolName: encrypted ? "https" : "http"
    )
    server.stop()
    configureServer()
    if started {
      do {
        try server.start()
        serverRunning = true
      } catch {
        serverRunning = false
        errorMessage = error.localizedDescription
      }
    } else {
      serverRunning = false
    }
    publishInfo()
    publishDownloads()
    announcePresence()
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
      deviceModel: settings.deviceModel,
      deviceType: settings.deviceType,
      port: settings.port,
      protocolName: settings.encryption && !webReceiveMode && webSendFiles == nil ? "https" : "http"
    )
    publishInfo()
  }

  private func publishInfo() {
    infoBox.set(deviceIdentity.infoDTO(downloadEnabled: settings.downloadEnabled))
  }

  private func configureServer() {
    server.identity = identity
    server.encryption = settings.encryption && !webReceiveMode && webSendFiles == nil
    server.verifyChecksums = settings.verifyChecksums
    server.webUploadEnabled = webReceiveMode
    server.webSendEnabled = webSendFiles != nil
    server.pin = webSendFiles != nil || settings.pin.isEmpty ? nil : settings.pin
    server.port = settings.port
    if let webSendFiles {
      let files = webSendFiles.map {
        FileDTO(id: $0.id, fileName: $0.name, size: $0.size, fileType: $0.fileType)
      }
      let urls = Dictionary(uniqueKeysWithValues: webSendFiles.map { ($0.id, $0.url) })
      server.downloadProvider = { files }
      server.downloadURLProvider = { urls[$0.id] }
    } else {
      server.downloadProvider = settings.downloadEnabled ? { [downloadBox] in downloadBox.value } : nil
      server.downloadURLProvider = nil
    }
    server.identityProvider = { [infoBox] in infoBox.value }
    let destinationBox = destination.box
    server.destinationProvider = { destinationBox.value ?? LocalHTTPServer.downloadsDirectory() }
    server.onEvent = { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
  }

  func beginWebReceive() {
    guard !webReceiveMode else { return }
    webReceiveMode = true
    applyNetworkSettings()
  }

  func endWebReceive() {
    guard webReceiveMode else { return }
    webReceiveMode = false
    applyNetworkSettings()
  }

  func beginWebSend(files: [SelectedFile]) {
    guard !files.isEmpty else { return }
    webSendFiles = files
    applyNetworkSettings()
  }

  func endWebSend() {
    guard webSendFiles != nil else { return }
    webSendFiles = nil
    applyNetworkSettings()
  }

  // MARK: Server events

  private func handle(_ event: ServerEvent) {
    switch event {
    case let .incoming(sessionId, peerAlias, peerFingerprint, files):
      activePeerAlias = peerAlias
      activePeerFingerprint = peerFingerprint
      let request = IncomingRequest(id: sessionId, peerAlias: peerAlias, files: files)
      let favourite = favorites.devices.contains { $0.fingerprint == peerFingerprint }
      if settings.quickSave || (settings.quickSaveFromFavorites && favourite) {
        accept(request)
      } else {
        incoming = request
      }

    case let .received(fileName, url):
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      let file = ReceivedFile(id: url.path, name: fileName, url: url, size: size, date: Date())
      receivedFiles.insert(file, at: 0)
      if settings.saveHistory {
        history.add(
          direction: .received,
          alias: activePeerAlias.isEmpty ? "LocalSend Plus" : activePeerAlias,
          files: [HistoryFile(name: fileName, size: Int64(size), relativePath: fileName)]
        )
      }
      if settings.saveToPhotos, PhotoSaver.isMedia(url) {
        Task { await PhotoSaver.save([url]) }
      }
      publishDownloads()

    case let .peerSeen(peer):
      // The peer reached us, but its protocol is unknown: resolve it the same way a scan would.
      Task { [weak self] in
        guard let self else { return }
        if let device = await DeviceProbe.info(host: peer.host, identity: self.identity, timeout: self.settings.discoveryTimeout) {
          self.discovery.absorb(device)
        }
      }
    }
  }

  // MARK: Receiving

  func accept(_ request: IncomingRequest, acceptedIds: Set<String>? = nil) {
    server.decide(sessionId: request.id, acceptedIds: acceptedIds ?? Set(request.files.map(\.id)))
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
      if settings.saveHistory {
        history.add(
          direction: .sent,
          alias: device.alias,
          files: files.map { HistoryFile(name: $0.name, size: Int64($0.size), relativePath: nil) }
        )
      }
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
