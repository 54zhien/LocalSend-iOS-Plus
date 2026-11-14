import Foundation
import Security

enum TransferError: LocalizedError {
  case declined
  case pinRequired
  case tooManyAttempts
  case blocked
  case noFiles
  case cancelled
  case http(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .declined: return String(localized: "The receiver declined the transfer.")
    case .pinRequired: return String(localized: "The receiver requires a PIN.")
    case .tooManyAttempts: return String(localized: "Too many wrong PIN attempts. Try again later.")
    case .blocked: return String(localized: "The receiver is busy with another session.")
    case .noFiles: return String(localized: "Select at least one file.")
    case .cancelled: return String(localized: "The transfer was cancelled.")
    case let .http(status, message): return "HTTP \(status): \(message)"
    }
  }
}

/// URLSession trust behaviour for LocalSend peers.
enum TrustPolicy {
  /// Accept whatever certificate the peer presents (used for discovery, before the
  /// announced fingerprint is known).
  case acceptAny
  /// Compare the leaf certificate's SHA-256 with the announced fingerprint.
  case pin(String?)
}

final class LocalSendSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
  private let identity: LocalIdentity
  private let policy: TrustPolicy

  init(identity: LocalIdentity, policy: TrustPolicy) {
    self.identity = identity
    self.policy = policy
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    handle(challenge, completionHandler: completionHandler)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    handle(challenge, completionHandler: completionHandler)
  }

  private func handle(
    _ challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let method = challenge.protectionSpace.authenticationMethod

    if method == NSURLAuthenticationMethodClientCertificate {
      if let secIdentity = identity.identity, let certificate = identity.certificate {
        completionHandler(
          .useCredential,
          URLCredential(identity: secIdentity, certificates: [certificate], persistence: .forSession)
        )
      } else {
        completionHandler(.performDefaultHandling, nil)
      }
      return
    }

    guard method == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust else {
      completionHandler(.performDefaultHandling, nil)
      return
    }

    if case let .pin(expected) = policy, let expected, !expected.isEmpty {
      guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
        let leaf = chain.first
      else {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
      }
      let fingerprint = Hex.sha256(SecCertificateCopyData(leaf) as Data)
      if fingerprint.caseInsensitiveCompare(expected) != .orderedSame {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
      }
    }

    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}

/// Client side of `prepare-upload` + `upload`, matching the Rust client:
/// TLS with the local identity when the peer speaks https, PIN in the query,
/// token-checked uploads, and the same status-code semantics.
struct TransferSender {
  struct Outcome {
    let sessionId: String
    let uploaded: Int
  }

  let identity: LocalIdentity
  let settings: AppSettings

  @MainActor
  func send(
    files: [SelectedFile],
    to device: Device,
    identity own: DeviceIdentity,
    pin: String? = nil,
    onSession: ((String) -> Void)? = nil,
    onProgress: @escaping @MainActor (Int, Int) -> Void
  ) async throws -> Outcome {
    guard !files.isEmpty else { throw TransferError.noFiles }

    let encrypted = device.protocolName == "https"
    let delegate = LocalSendSessionDelegate(
      identity: identity,
      policy: encrypted ? .pin(device.fingerprint) : .acceptAny
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }

    guard let base = device.baseURL(encrypted: encrypted) else {
      throw TransferError.http(status: 0, message: "invalid peer address")
    }
    let info = own.infoDTO(downloadEnabled: settings.downloadEnabled)

    let shouldHash = settings.createChecksums
    let hashTargets = files.map { (id: $0.id, url: $0.url) }
    let hashes = try await Task.detached(priority: .userInitiated) {
      var results: [String: String] = [:]
      if shouldHash {
        for target in hashTargets {
          let scoped = target.url.startAccessingSecurityScopedResource()
          defer { if scoped { target.url.stopAccessingSecurityScopedResource() } }
          results[target.id] = try FileHash.sha256(of: target.url)
        }
      }
      return results
    }.value

    var fileMap: [String: FileDTO] = [:]
    for file in files {
      fileMap[file.id] = FileDTO(
        id: file.id,
        fileName: file.name,
        size: file.size,
        fileType: file.fileType,
        sha256: hashes[file.id]
      )
    }

    var prepareURL = base.appendingPathComponent("api/localsend/v2/prepare-upload")
    if let pin, !pin.isEmpty {
      prepareURL = prepareURL.appending(queryItems: [URLQueryItem(name: "pin", value: pin)])
    }

    var request = URLRequest(url: prepareURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(PrepareUploadRequest(info: info, files: fileMap))

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw TransferError.cancelled }

    switch http.statusCode {
    case 200: break
    case 204: throw TransferError.declined
    case 401: throw TransferError.pinRequired
    case 403: throw TransferError.http(status: 403, message: Self.message(from: data))
    case 409: throw TransferError.blocked
    case 429: throw TransferError.tooManyAttempts
    default: throw TransferError.http(status: http.statusCode, message: Self.message(from: data))
    }

    let prepared = try JSONDecoder().decode(PrepareUploadResponse.self, from: data)
    onSession?(prepared.sessionId)
    var uploaded = 0

    for file in files {
      guard let token = prepared.files[file.id] else { continue }

      var components = URLComponents(
        url: base.appendingPathComponent("api/localsend/v2/upload"),
        resolvingAgainstBaseURL: false
      )
      components?.queryItems = [
        URLQueryItem(name: "sessionId", value: prepared.sessionId),
        URLQueryItem(name: "fileId", value: file.id),
        URLQueryItem(name: "token", value: token),
      ]
      guard let url = components?.url else { continue }

      var upload = URLRequest(url: url)
      upload.httpMethod = "POST"
      upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

      let scoped = file.url.startAccessingSecurityScopedResource()
      defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }

      let (body, uploadResponse) = try await session.upload(for: upload, fromFile: file.url)
      guard let uploadHTTP = uploadResponse as? HTTPURLResponse, uploadHTTP.statusCode == 200 else {
        let status = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
        throw TransferError.http(status: status, message: Self.message(from: body))
      }

      uploaded += 1
      onProgress(uploaded, files.count)
    }

    return Outcome(sessionId: prepared.sessionId, uploaded: uploaded)
  }

  /// Best-effort cancel of a running session on the receiver.
  @MainActor
  func cancel(sessionId: String, device: Device) async {
    let encrypted = device.protocolName == "https"
    let delegate = LocalSendSessionDelegate(
      identity: identity,
      policy: encrypted ? .pin(device.fingerprint) : .acceptAny
    )
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    guard let base = device.baseURL(encrypted: encrypted) else { return }
    var components = URLComponents(
      url: base.appendingPathComponent("api/localsend/v2/cancel"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
    guard let url = components?.url else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    _ = try? await session.data(for: request)
    session.finishTasksAndInvalidate()
  }

  private static func message(from data: Data) -> String {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let message = object["message"] as? String
    {
      return message
    }
    let text = String(decoding: data, as: UTF8.self)
    return text.isEmpty ? "-" : String(text.prefix(120))
  }
}
