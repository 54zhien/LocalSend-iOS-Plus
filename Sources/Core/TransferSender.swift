import Foundation

enum TransferError: LocalizedError {
  case declined
  case pinRequired
  case blocked
  case http(status: Int, message: String)
  case noFiles

  var errorDescription: String? {
    switch self {
    case .declined: return "The other device declined the transfer."
    case .pinRequired: return "The other device requires a PIN."
    case .blocked: return "The other device blocked this sender."
    case let .http(status, message): return "HTTP \(status): \(message)"
    case .noFiles: return "No files selected."
    }
  }
}

/// Sends files with the LocalSend v2 protocol:
/// `POST /prepare-upload` for the session and per-file tokens, then `POST /upload` per file.
struct TransferSender {
  struct Outcome {
    let sessionId: String
    let uploaded: Int
  }

  func send(
    files: [SelectedFile],
    to device: Device,
    identity: DeviceIdentity,
    downloadEnabled: Bool,
    onProgress: @escaping @MainActor (Int, Int) -> Void
  ) async throws -> Outcome {
    guard !files.isEmpty else { throw TransferError.noFiles }
    guard let base = device.baseURL else { throw TransferError.http(status: 0, message: "bad address") }

    var payload: [String: FileDTO] = [:]
    for file in files {
      payload[file.id] = FileDTO(
        id: file.id,
        fileName: file.name,
        size: file.size,
        fileType: file.fileType,
        sha256: nil,
        preview: nil
      )
    }

    let request = PrepareUploadRequest(info: identity.infoDTO(downloadEnabled: downloadEnabled), files: payload)
    var prepare = URLRequest(url: base.appendingPathComponent("api/localsend/v2/prepare-upload"))
    prepare.httpMethod = "POST"
    prepare.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    prepare.httpBody = try JSONEncoder().encode(request)

    let (data, response) = try await URLSession.shared.data(for: prepare)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200:
      break
    case 204:
      throw TransferError.declined
    case 403:
      throw TransferError.pinRequired
    case 409:
      throw TransferError.blocked
    default:
      throw TransferError.http(status: status, message: String(decoding: data, as: UTF8.self))
    }

    let prepared = try JSONDecoder().decode(PrepareUploadResponse.self, from: data)
    var uploaded = 0
    await onProgress(0, files.count)

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
      defer {
        if scoped { file.url.stopAccessingSecurityScopedResource() }
      }
      let (body, uploadResponse) = try await URLSession.shared.upload(for: upload, fromFile: file.url)
      let uploadStatus = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
      guard uploadStatus == 200 else {
        throw TransferError.http(status: uploadStatus, message: String(decoding: body, as: UTF8.self))
      }
      uploaded += 1
      await onProgress(uploaded, files.count)
    }

    return Outcome(sessionId: prepared.sessionId, uploaded: uploaded)
  }
}
