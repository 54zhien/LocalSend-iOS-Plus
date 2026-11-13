import Foundation
import Network
import UIKit

/// Minimal HTTP/1.1 server for the LocalSend v2 receive path.
///
/// Routes:
///   GET  /api/localsend/v2/info           → device info (also answers v1)
///   POST /api/localsend/v2/register       → device info, and the caller is recorded as a peer
///   POST /api/localsend/v2/prepare-upload → session + one token per file (all accepted)
///   POST /api/localsend/v2/upload         → body is streamed straight to disk
///   POST /api/localsend/v2/cancel         → session teardown
///
/// One request per connection; every response carries `Connection: close`.
final class LocalHTTPServer {
  private let queue = DispatchQueue(label: "org.localsend.http.server")
  private var listener: NWListener?
  private var sessions: [String: [String: FileDTO]] = [:]

  private(set) var isRunning = false
  private(set) var port: Int = 53317

  var identityProvider: () -> DeviceInfoDTO = {
    DeviceInfoDTO(
      alias: "LocalSend",
      version: "2.2",
      deviceModel: nil,
      deviceType: DeviceType.mobile.rawValue,
      fingerprint: "unknown",
      port: 53317,
      protocolName: "http",
      download: false
    )
  }
  var onSession: ((String, [String], String) -> Void)?
  var onFileReceived: ((String, URL) -> Void)?
  var onPeerSeen: ((DeviceInfoDTO, String) -> Void)?

  // MARK: Lifecycle

  func start() throws {
    guard !isRunning else { return }
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
    let listener = try NWListener(using: parameters, on: nwPort)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      HTTPConnection(connection: connection, server: self, queue: self.queue).start()
    }
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.isRunning = true
      case .failed, .cancelled:
        self.isRunning = false
      default:
        break
      }
    }
    listener.start(queue: queue)
    self.listener = listener
  }

  func stop() {
    listener?.cancel()
    listener = nil
    isRunning = false
  }

  // MARK: Routing (always on `queue`)

  fileprivate func route(connection: HTTPConnection, method: String, path: String, body: Data) {
    let pathOnly = path.split(separator: "?").first.map(String.init) ?? path
    switch (method, pathOnly) {
    case ("GET", "/api/localsend/v2/info"), ("GET", "/api/localsend/v1/info"):
      connection.respondJSON(status: 200, value: identityProvider())

    case ("POST", "/api/localsend/v2/register"):
      if let dto = try? JSONDecoder().decode(DeviceInfoDTO.self, from: body) {
        let peer = connection.peerAddress
        if let callback = onPeerSeen {
          DispatchQueue.main.async { callback(dto, peer) }
        }
      }
      connection.respondJSON(status: 200, value: identityProvider())

    case ("POST", "/api/localsend/v2/prepare-upload"):
      guard let request = try? JSONDecoder().decode(PrepareUploadRequest.self, from: body) else {
        connection.respondJSON(status: 400, value: ["message": "invalid body"])
        return
      }
      let sessionId = UUID().uuidString
      var tokens: [String: String] = [:]
      for fileId in request.files.keys {
        tokens[fileId] = UUID().uuidString
      }
      sessions[sessionId] = request.files
      let peer = connection.peerAddress
      let names = request.files.values.map(\.fileName)
      if let callback = onSession {
        DispatchQueue.main.async { callback(sessionId, names, peer) }
      }
      connection.respondJSON(status: 200, value: PrepareUploadResponse(sessionId: sessionId, files: tokens))

    case ("POST", "/api/localsend/v2/cancel"):
      if let sessionId = Self.query(path: path, key: "sessionId") {
        sessions.removeValue(forKey: sessionId)
      }
      connection.respond(status: 200, body: Data(), contentType: "text/plain")

    default:
      connection.respondJSON(status: 404, value: ["message": "not found"])
    }
  }

  /// Opens the destination file for an upload request.
  fileprivate func beginUpload(path: String) -> (FileHandle, URL)? {
    let sessionId = Self.query(path: path, key: "sessionId") ?? ""
    let fileId = Self.query(path: path, key: "fileId") ?? ""
    let name = sessions[sessionId]?[fileId]?.fileName ?? "file"
    let directory = Self.downloadsDirectory()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = Self.uniqueURL(in: directory, name: name)
    guard FileManager.default.createFile(atPath: target.path, contents: nil) else { return nil }
    guard let handle = try? FileHandle(forWritingTo: target) else { return nil }
    return (handle, target)
  }

  fileprivate func completeUpload(url: URL) {
    if let callback = onFileReceived {
      DispatchQueue.main.async { callback(url.lastPathComponent, url) }
    }
  }

  // MARK: Helpers

  static func downloadsDirectory() -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("LocalSend", isDirectory: true)
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
  private var isClosed = false

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
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
      guard let self, !self.isClosed else { return }
      if let data, !data.isEmpty {
        self.consume(data)
      }
      if error != nil || isComplete {
        self.close()
        return
      }
      if !self.isClosed {
        self.receive()
      }
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
      let pathOnly = path.split(separator: "?").first.map(String.init) ?? path
      isUpload = method == "POST" && pathOnly == "/api/localsend/v2/upload"

      if isUpload {
        guard let (handle, url) = server.beginUpload(path: path) else {
          respondJSON(status: 500, value: ["message": "cannot store file"])
          return
        }
        fileHandle = handle
        fileURL = url
        remaining = bodyLength
        if remaining == 0 {
          finishUpload()
          return
        }
      } else if bodyLength == 0 {
        routeOnce(body: Data())
        return
      }
    }

    guard !isClosed else { return }

    if isUpload {
      if !chunk.isEmpty {
        writeToFile(chunk)
      }
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
    server.route(connection: self, method: method, path: path, body: body)
  }

  private func writeToFile(_ data: Data) {
    guard remaining > 0, let handle = fileHandle else { return }
    let slice = data.prefix(remaining)
    handle.write(Data(slice))
    remaining -= slice.count
    if remaining <= 0 {
      finishUpload()
    }
  }

  private func finishUpload() {
    fileHandle?.closeFile()
    fileHandle = nil
    didRoute = true
    if let url = fileURL {
      server.completeUpload(url: url)
    }
    respond(status: 200, body: Data(), contentType: "application/octet-stream")
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
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 204: reason = "No Content"
    case 400: reason = "Bad Request"
    case 403: reason = "Forbidden"
    case 404: reason = "Not Found"
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
  }
}
