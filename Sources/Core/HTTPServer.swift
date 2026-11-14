import Foundation
import Network
import UIKit

/// Events the app has to answer, mirroring the Flutter client's session model.
enum ServerEvent {
  /// A sender asked to upload files. The app must call `decide` or `decline`.
  case incoming(sessionId: String, peerAlias: String, peerFingerprint: String, files: [FileDTO])
  case received(fileName: String, url: URL)
  case peerSeen(PeerDescription)
  case downloadRequested(id: String, peerIp: String)

  struct PeerDescription {
    let alias: String
    let deviceType: String?
    let fingerprint: String
    let host: String
    let port: Int
  }
}

/// HTTP/HTTPS server for the LocalSend v2 receive path.
///
/// Mirrors `packages/core/src/http/server`:
///   GET/POST /api/localsend/v2/info, /api/localsend/v2/register,
///   POST /api/localsend/v2/prepare-upload (PIN, 409 on a running session, approval),
///   POST /api/localsend/v2/upload (token + sender IP validation),
///   POST /api/localsend/v2/cancel,
///   POST /api/localsend/v2/prepare-download + GET /api/localsend/v2/download (web share).
final class LocalHTTPServer {
  struct Session {
    let id: String
    let peerIp: String
    let peerAlias: String
    let peerFingerprint: String
    var files: [String: FileDTO]
    var tokens: [String: String]
    var accepted: Set<String>?
    var connection: HTTPConnection?
    var receivedIds: Set<String> = []
    var startedAt = Date()
  }

  private let queue = DispatchQueue(label: "org.localsend.http.server")
  private var listener: NWListener?
  /// Retains every live connection: the receive callbacks hold self weakly, so without
  /// this the object is deallocated immediately after start() and the peer never gets a reply.
  private var connections: [ObjectIdentifier: HTTPConnection] = [:]
  /// Guards against a cancelled listener reporting a stale state after a restart.
  private var generation = 0
  private var sessions: [String: Session] = [:]
  private var activeSessionId: String?
  private var pinFailures: [String: Int] = [:]
  private var downloadSession: (id: String, files: [String: FileDTO], tokens: [String: String])?
  private var pendingDownloads: [String: HTTPConnection] = [:]

  private(set) var isRunning = false
  var port: Int = 53317

  var identity: LocalIdentity = LocalIdentity.load()
  var encryption = true
  var pin: String?
  /// `nil` disables the web download API; otherwise the files offered to browsers.
  var downloadProvider: (() -> [FileDTO])?
  var downloadURLProvider: ((FileDTO) -> URL?)?
  var webUploadEnabled = false
  var webSendEnabled = false
  var webSendAutoAccept = false
  var verifyChecksums = true
  /// Where received files are written; falls back to `Documents/LocalSend`.
  var destinationProvider: (() -> URL)?
  var onEvent: ((ServerEvent) -> Void)?
  /// Reports the listener's real state on the server queue. The UI must not assume the
  /// port was acquired: `NWListener` fails asynchronously, long after `start()` returns.
  var onStateChange: ((Bool, String?) -> Void)?

  var identityProvider: () -> DeviceInfoDTO = {
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
  }

  // MARK: Lifecycle

  func start() throws {
    guard !isRunning else { return }
    generation += 1
    let currentGeneration = generation

    let parameters: NWParameters
    if encryption, identity.identity != nil {
      let tls = TLS.serverOptions(identity: identity, requireClientCertificate: downloadProvider == nil)
      parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    } else {
      parameters = NWParameters.tcp
    }
    parameters.allowLocalEndpointReuse = true

    guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
    let listener = try NWListener(using: parameters, on: nwPort)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      let conn = HTTPConnection(connection: connection, server: self, queue: self.queue)
      let key = ObjectIdentifier(conn)
      self.connections[key] = conn
      conn.onClose = { [weak self] in
        self?.queue.async { self?.connections.removeValue(forKey: key) }
      }
      conn.start()
    }
    listener.stateUpdateHandler = { [weak self] state in
      guard let self, currentGeneration == self.generation else { return }
      switch state {
      case .ready:
        self.isRunning = true
        self.onStateChange?(true, nil)
      case .failed(let error):
        self.isRunning = false
        self.onStateChange?(false, String(describing: error))
      case .cancelled:
        self.isRunning = false
        self.onStateChange?(false, nil)
      default:
        break
      }
    }
    listener.start(queue: queue)
    self.listener = listener
  }

  func stop() {
    generation += 1
    listener?.cancel()
    listener = nil
    isRunning = false
    sessions.removeAll()
    pendingDownloads.removeAll()
    activeSessionId = nil
  }

  // MARK: Decisions

  /// Answer a pending upload. `acceptedIds == nil` means "decline everything".
  func decide(sessionId: String, acceptedIds: Set<String>?) {
    queue.async { [weak self] in
      guard let self, var session = self.sessions[sessionId] else { return }

      guard let acceptedIds else {
        self.sessions.removeValue(forKey: sessionId)
        self.activeSessionId = nil
        session.connection?.respond(status: 204, body: Data(), contentType: "text/plain")
        return
      }

      session.accepted = acceptedIds
      self.sessions[sessionId] = session
      let tokens = session.tokens.filter { acceptedIds.contains($0.key) }
      session.connection?.respondJSON(
        status: 200,
        value: PrepareUploadResponse(sessionId: sessionId, files: tokens)
      )
    }
  }

  func cancel(sessionId: String) {
    queue.async { [weak self] in
      self?.sessions.removeValue(forKey: sessionId)
      if self?.activeSessionId == sessionId {
        self?.activeSessionId = nil
      }
    }
  }

  // MARK: Routing (runs on `queue`)

  fileprivate func route(
    connection: HTTPConnection,
    method: String,
    path: String,
    body: Data,
    peerIp: String
  ) {
    let trimmedPath = path.split(separator: "?").first.map(String.init) ?? path
    let pathOnly = trimmedPath.isEmpty ? "/" : trimmedPath

    switch (method, pathOnly) {
    case ("GET", "/"), ("GET", "/index.html"):
      handleDownloadPage(connection: connection)

    case ("GET", "/web/files"):
      if webSendEnabled, let files = downloadProvider?() {
        connection.respondJSON(status: 200, value: files)
      } else {
        connection.respondJSON(status: 404, value: ["message": "not found"])
      }

    case ("GET", "/api/localsend/v2/info"), ("GET", "/api/localsend/v1/info"):
      connection.respondJSON(status: 200, value: identityProvider())

    case ("POST", "/api/localsend/v2/register"):
      if let dto = try? JSONDecoder().decode(DeviceInfoDTO.self, from: body) {
        onEvent?(.peerSeen(ServerEvent.PeerDescription(
          alias: dto.alias,
          deviceType: dto.deviceType,
          fingerprint: dto.fingerprint,
          host: peerIp,
          port: dto.port ?? 53317
        )))
      }
      connection.respondJSON(status: 200, value: identityProvider())

    case ("POST", "/api/localsend/v2/prepare-upload"):
      handlePrepareUpload(connection: connection, body: body, path: path, peerIp: peerIp)

    case ("POST", "/api/localsend/v2/upload"):
      handleUploadStart(connection: connection, path: path, peerIp: peerIp)

    case ("POST", "/api/localsend/v2/cancel"):
      if let sessionId = Self.query(path: path, key: "sessionId") {
        sessions.removeValue(forKey: sessionId)
        if activeSessionId == sessionId { activeSessionId = nil }
      }
      connection.respond(status: 200, body: Data(), contentType: "text/plain")

    case ("POST", "/api/localsend/v2/prepare-download"):
      handlePrepareDownload(connection: connection, path: path)

    case ("GET", "/api/localsend/v2/download"):
      handleDownload(connection: connection, path: path)

    default:
      connection.respondJSON(status: 404, value: ["message": "not found"])
    }
  }

  // MARK: Handlers

  private func handlePrepareUpload(
    connection: HTTPConnection,
    body: Data,
    path: String,
    peerIp: String
  ) {
    if let pin, !pin.isEmpty {
      let attempts = pinFailures[peerIp] ?? 0
      if attempts >= 3 {
        connection.respondJSON(status: 429, value: ["message": "Too many requests"])
        return
      }
      guard let provided = Self.query(path: path, key: "pin") else {
        connection.respondJSON(status: 401, value: ["message": "PIN required"])
        return
      }
      guard provided == pin else {
        pinFailures[peerIp] = attempts + 1
        connection.respondJSON(status: 401, value: ["message": "Invalid PIN"])
        return
      }
      pinFailures.removeValue(forKey: peerIp)
    }

    guard let request = try? JSONDecoder().decode(PrepareUploadRequest.self, from: body) else {
      connection.respondJSON(status: 400, value: ["message": "invalid body"])
      return
    }

    if let activeSessionId, sessions[activeSessionId]?.accepted != nil {
      connection.respondJSON(status: 409, value: ["message": "Blocked by another session"])
      return
    }

    let sessionId = UUID().uuidString
    var tokens: [String: String] = [:]
    for fileId in request.files.keys {
      tokens[fileId] = UUID().uuidString
    }

    var session = Session(
      id: sessionId,
      peerIp: peerIp,
      peerAlias: request.info.alias,
      peerFingerprint: request.info.fingerprint,
      files: request.files,
      tokens: tokens
    )
    session.connection = connection
    sessions[sessionId] = session
    activeSessionId = sessionId

    onEvent?(.incoming(
      sessionId: sessionId,
      peerAlias: request.info.alias,
      peerFingerprint: request.info.fingerprint,
      files: request.files.values.sorted { $0.fileName < $1.fileName }
    ))

    // Auto-decline when nobody answers within two minutes.
    queue.asyncAfter(deadline: .now() + 120) { [weak self] in
      guard let self, self.sessions[sessionId]?.accepted == nil else { return }
      self.decide(sessionId: sessionId, acceptedIds: nil)
    }
  }

  private func handleUploadStart(connection: HTTPConnection, path: String, peerIp: String) {
    guard
      let sessionId = Self.query(path: path, key: "sessionId"),
      let fileId = Self.query(path: path, key: "fileId"),
      let token = Self.query(path: path, key: "token")
    else {
      connection.respondJSON(status: 400, value: ["message": "Missing parameters"])
      return
    }

    guard var session = sessions[sessionId],
      session.peerIp == peerIp,
      session.tokens[fileId] == token,
      session.accepted?.contains(fileId) == true,
      let file = session.files[fileId]
    else {
      connection.respondJSON(status: 403, value: ["message": "Invalid token"])
      return
    }

    guard let handle = openDestination(for: file.fileName, connection: connection) else {
      connection.respondJSON(status: 500, value: ["message": "cannot store file"])
      return
    }

    session.receivedIds.insert(fileId)
    sessions[sessionId] = session

    connection.beginFileUpload(handle: handle.handle, url: handle.url) { [weak self] name, url in
      guard let self else { return false }
      if self.verifyChecksums, let expected = file.sha256 {
        guard let actual = try? FileHash.sha256(of: url),
          actual.caseInsensitiveCompare(expected) == .orderedSame
        else {
          try? FileManager.default.removeItem(at: url)
          self.sessions.removeValue(forKey: sessionId)
          self.activeSessionId = nil
          return false
        }
      }
      self.onEvent?(.received(fileName: name, url: url))

      self.queue.async {
        guard var current = self.sessions[sessionId] else { return }
        current.receivedIds.insert(fileId)
        self.sessions[sessionId] = current
        if current.receivedIds.count >= (current.accepted?.count ?? 0) {
          self.activeSessionId = nil
        }
      }
      return true
    }
  }

  private func handlePrepareDownload(connection: HTTPConnection, path: String) {
    guard let downloadProvider else {
      connection.respondJSON(status: 404, value: ["message": "not found"])
      return
    }

    if let pin, !pin.isEmpty, Self.query(path: path, key: "pin") != pin {
      connection.respondJSON(status: 401, value: ["message": "PIN required"])
      return
    }

    if webSendEnabled && !webSendAutoAccept && !pendingDownloads.isEmpty {
      connection.respondJSON(status: 409, value: ["message": "Another download request is pending"])
      return
    }

    let files = downloadProvider()
    var tokens: [String: String] = [:]
    for file in files { tokens[file.id] = UUID().uuidString }
    let sessionId = UUID().uuidString
    downloadSession = (sessionId, Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }), tokens)

    if webSendEnabled && !webSendAutoAccept {
      pendingDownloads[sessionId] = connection
      onEvent?(.downloadRequested(id: sessionId, peerIp: connection.peerAddress))
    } else {
      connection.respondJSON(
        status: 200,
        value: PrepareUploadResponse(sessionId: sessionId, files: tokens)
      )
    }
  }

  func decideDownload(id: String, accepted: Bool) {
    queue.async { [weak self] in
      guard let self, let connection = self.pendingDownloads.removeValue(forKey: id) else { return }
      guard accepted, let session = self.downloadSession, session.id == id else {
        connection.respondJSON(status: 403, value: ["message": "Download declined"])
        return
      }
      connection.respondJSON(status: 200, value: PrepareUploadResponse(sessionId: id, files: session.tokens))
    }
  }

  private func handleDownload(connection: HTTPConnection, path: String) {
    guard let downloadSession,
      Self.query(path: path, key: "sessionId") == downloadSession.id,
      let fileId = Self.query(path: path, key: "fileId"),
      let token = Self.query(path: path, key: "token"),
      downloadSession.tokens[fileId] == token,
      let file = downloadSession.files[fileId],
      let url = downloadURL(for: file)
    else {
      connection.respondJSON(status: 403, value: ["message": "Invalid token"])
      return
    }

    guard let data = try? Data(contentsOf: url) else {
      connection.respondJSON(status: 404, value: ["message": "not found"])
      return
    }
    connection.respond(status: 200, body: data, contentType: file.fileType)
  }

  private func handleDownloadPage(connection: HTTPConnection) {
    if webSendEnabled,
      let url = Bundle.main.url(forResource: "web-download", withExtension: "html"),
      let body = try? Data(contentsOf: url)
    {
      connection.respond(status: 200, body: body, contentType: "text/html; charset=utf-8")
      return
    }
    if webUploadEnabled,
      let url = Bundle.main.url(forResource: "web-upload", withExtension: "html"),
      let body = try? Data(contentsOf: url)
    {
      connection.respond(status: 200, body: body, contentType: "text/html; charset=utf-8")
      return
    }
    guard downloadProvider != nil else {
      connection.respondJSON(status: 404, value: ["message": "not found"])
      return
    }
    connection.respond(status: 200, body: Data(Self.downloadHTML.utf8), contentType: "text/html; charset=utf-8")
  }

  private func downloadURL(for file: FileDTO) -> URL? {
    if let url = downloadURLProvider?(file) { return url }
    let directory = Self.downloadsDirectory()
    let candidate = directory.appendingPathComponent(file.fileName)
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
  }

  func openDestination(for name: String, connection: HTTPConnection) -> (handle: FileHandle, url: URL)? {
    let directory = destinationProvider?() ?? Self.downloadsDirectory()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = Self.uniqueURL(in: directory, name: name)
    guard FileManager.default.createFile(atPath: target.path, contents: nil),
      let handle = try? FileHandle(forWritingTo: target)
    else {
      return nil
    }
    return (handle, target)
  }

  // MARK: Helpers

  static func downloadsDirectory() -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("LocalSend Plus", isDirectory: true)
  }

  static func uniqueURL(in directory: URL, name: String) -> URL {
    let candidate = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var index = 1
    while true {
      let suffix = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
      let url = directory.appendingPathComponent(suffix)
      if !FileManager.default.fileExists(atPath: url.path) { return url }
      index += 1
    }
  }

  static func query(path: String, key: String) -> String? {
    guard let questionMark = path.firstIndex(of: "?") else { return nil }
    let query = path[path.index(after: questionMark)...]
    for pair in query.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard parts.count == 2, parts[0] == Substring(key) else { continue }
      return String(parts[1]).removingPercentEncoding ?? String(parts[1])
    }
    return nil
  }

  private static let downloadHTML = """
    <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>LocalSend</title>
    <style>
      body{font:16px -apple-system,system-ui;margin:0;padding:24px;background:#0b0b0f;color:#f2f2f7}
      h1{font-size:22px;margin:0 0 16px}ul{list-style:none;padding:0;margin:0}
      li{padding:14px;margin-bottom:8px;border-radius:16px;background:rgba(255,255,255,.08)}
      a{color:#64d2ff;text-decoration:none}small{opacity:.6}
    </style>
    <h1>LocalSend</h1>
    <p><small>Open the LocalSend app on the receiving device to list shared files.</small></p>
    """
}

// MARK: - Connection

final class HTTPConnection {
  private let connection: NWConnection
  private let server: LocalHTTPServer
  private let queue: DispatchQueue

  private var buffer = Data()
  private var headersParsed = false
  private var method = ""
  private var path = ""
  private var headers: [String: String] = [:]
  private var bodyLength = 0
  private var body = Data()
  private var isUpload = false
  private var remaining = 0
  private var fileHandle: FileHandle?
  private var fileURL: URL?
  private var didRoute = false
  private var didRespond = false
  private var prefetched = Data()
  // Streamed uploads (reqwest `Body::wrap_stream`) carry Transfer-Encoding: chunked and no
  // Content-Length, so the body has to be de-framed here instead of being counted.
  private var chunked = false
  private var unbounded = false
  private var chunkBuffer = Data()
  private var chunkRemaining = 0
  private var expectsChunkCRLF = false
  private static let crlf = Data("\r\n".utf8)
  private var isClosed = false
  private var onFinish: ((String, URL) -> Bool)?
  /// Called once when the connection is torn down, so the server can release it.
  var onClose: (() -> Void)?

  private static let headerTerminator = Data("\r\n\r\n".utf8)

  init(connection: NWConnection, server: LocalHTTPServer, queue: DispatchQueue) {
    self.connection = connection
    self.server = server
    self.queue = queue
  }

  var peerAddress: String {
    if case let .hostPort(host, _) = connection.endpoint {
      return "\(host)"
    }
    return ""
  }

  func start() {
    connection.start(queue: queue)
    receive()
  }

  private func receive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
      guard let self, !self.isClosed else { return }
      if let data, !data.isEmpty { self.consume(data) }
      if error != nil {
        self.close()
        return
      }
      if isComplete {
        if self.isUpload, !self.didRespond, self.fileHandle != nil {
          self.finishUpload()
        } else {
          self.close()
        }
        return
      }
      if !self.isClosed { self.receive() }
    }
  }

  private func consume(_ data: Data) {
    var chunk = data

    if !headersParsed {
      buffer.append(data)
      guard let headerEnd = buffer.range(of: Self.headerTerminator) else { return }
      let headerBlock = Data(buffer[..<headerEnd.lowerBound])
      chunk = Data(buffer[headerEnd.upperBound...])
      buffer = Data()
      parseHeaders(String(decoding: headerBlock, as: UTF8.self))
      headersParsed = true

      if headers["expect"]?.lowercased().contains("100-continue") == true {
        send(raw: "HTTP/1.1 100 Continue\r\n\r\n")
      }

      bodyLength = Int(headers["content-length"] ?? "0") ?? 0
      chunked = headers["transfer-encoding"]?.lowercased().contains("chunked") == true
      let pathOnly = path.split(separator: "?").first.map(String.init) ?? path
      isUpload = method == "POST" && pathOnly == "/api/localsend/v2/upload"

      if isUpload {
        // Route first: the handler opens the destination and installs the file handle.
        if chunked {
          chunkBuffer.append(chunk)
          server.route(connection: self, method: method, path: path, body: Data(), peerIp: peerAddress)
          pumpChunked()
          return
        }
        if bodyLength == 0 { unbounded = true }
        prefetched = chunk
        server.route(connection: self, method: method, path: path, body: Data(), peerIp: peerAddress)
        return
      }

      if bodyLength == 0 {
        routeOnce(body: Data())
        return
      }
    }

    guard !isClosed else { return }

    if chunked {
      if !chunk.isEmpty { chunkBuffer.append(chunk) }
      pumpChunked()
    } else if isUpload {
      if !chunk.isEmpty { writeToFile(chunk) }
    } else {
      body.append(chunk)
      if body.count >= bodyLength {
        routeOnce(body: body)
      }
    }
  }

  private func routeOnce(body: Data) {
    guard !didRoute else { return }
    didRoute = true
    server.route(connection: self, method: method, path: path, body: body, peerIp: peerAddress)
  }

  // MARK: Upload sink

  func beginFileUpload(handle: FileHandle, url: URL, onFinish: @escaping (String, URL) -> Bool) {
    fileHandle = handle
    fileURL = url
    remaining = (chunked || unbounded || bodyLength == 0) ? Int.max : bodyLength
    self.onFinish = onFinish
    didRoute = true
    if remaining <= 0 { finishUpload() }
    // Continue consuming the body that arrived together with the headers.
    if !prefetched.isEmpty {
      let pending = prefetched
      prefetched = Data()
      writeToFile(pending)
    }
  }

  private func writeToFile(_ data: Data) {
    guard remaining > 0, let handle = fileHandle else { return }
    let slice = data.prefix(remaining)
    handle.write(Data(slice))
    remaining -= slice.count
    if remaining <= 0 { finishUpload() }
  }

  /// Decodes RFC 7230 chunked framing, writing payload bytes straight to the destination.
  private func pumpChunked() {
    while true {
      if expectsChunkCRLF {
        guard chunkBuffer.count >= 2 else { return }
        chunkBuffer.removeFirst(2)
        expectsChunkCRLF = false
      }

      if chunkRemaining == 0 {
        guard let crlf = chunkBuffer.range(of: Self.crlf) else { return }
        let line = String(decoding: chunkBuffer[..<crlf.lowerBound], as: UTF8.self)
        chunkBuffer.removeSubrange(chunkBuffer.startIndex..<crlf.upperBound)
        let sizeText = line.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) }
          ?? line
        guard let size = Int(sizeText, radix: 16) else {
          close()
          return
        }
        if size == 0 {
          if isUpload { finishUpload() } else { routeOnce(body: body) }
          return
        }
        chunkRemaining = size
      }

      guard !chunkBuffer.isEmpty else { return }
      let take = min(chunkRemaining, chunkBuffer.count)
      let piece = Data(chunkBuffer.prefix(take))
      chunkBuffer.removeFirst(take)
      chunkRemaining -= take
      if isUpload { writeToFile(piece) } else { body.append(piece) }
      if chunkRemaining == 0 { expectsChunkCRLF = true }
    }
  }

  private func finishUpload() {
    fileHandle?.closeFile()
    fileHandle = nil
    let valid = fileURL.map { onFinish?($0.lastPathComponent, $0) ?? false } ?? false
    respond(status: valid ? 200 : 422, body: Data(), contentType: "application/octet-stream")
  }

  private func parseHeaders(_ raw: String) {
    let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard let requestLine = lines.first else { return }
    let parts = requestLine.split(separator: " ")
    if parts.count >= 2 {
      method = String(parts[0]).uppercased()
      path = String(parts[1])
    }
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }
  }

  // MARK: Responses

  func respondJSON<T: Encodable>(status: Int, value: T) {
    let data = (try? JSONEncoder().encode(value)) ?? Data()
    respond(status: status, body: data, contentType: "application/json; charset=utf-8")
  }

  func respond(status: Int, body: Data, contentType: String) {
    guard !didRespond, !isClosed else { return }
    didRespond = true

    let reason: String
    switch status {
    case 200: reason = "OK"
    case 204: reason = "No Content"
    case 400: reason = "Bad Request"
    case 401: reason = "Unauthorized"
    case 403: reason = "Forbidden"
    case 404: reason = "Not Found"
    case 409: reason = "Conflict"
    case 422: reason = "Unprocessable Content"
    case 429: reason = "Too Many Requests"
    case 500: reason = "Internal Server Error"
    default: reason = "OK"
    }

    let head =
      "HTTP/1.1 \(status) \(reason)\r\n"
      + "Content-Type: \(contentType)\r\n"
      + "Content-Length: \(body.count)\r\n"
      + "Connection: close\r\n"
      + "\r\n"

    var payload = Data(head.utf8)
    payload.append(body)
    connection.send(
      content: payload,
      completion: .contentProcessed { [weak self] _ in
        self?.queue.async { self?.close() }
      }
    )
  }

  private func send(raw: String) {
    connection.send(content: Data(raw.utf8), completion: .contentProcessed { _ in })
  }

  private func close() {
    guard !isClosed else { return }
    isClosed = true
    fileHandle?.closeFile()
    fileHandle = nil
    connection.cancel()
    onClose?()
    onClose = nil
  }
}
