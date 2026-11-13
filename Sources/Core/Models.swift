import Foundation

/// Wire format of `/api/localsend/v2/*` and of the multicast announce packet.
/// Field names match the protocol exactly (camelCase, `protocol` is a keyword so it is renamed).

enum DeviceType: String, Codable, CaseIterable {
  case mobile
  case desktop
  case web
  case headless
  case server

  init(wire: String?) {
    self = DeviceType(rawValue: (wire ?? "").lowercased()) ?? .mobile
  }

  var symbolName: String {
    switch self {
    case .mobile: return "iphone"
    case .desktop: return "desktopcomputer"
    case .web: return "globe"
    case .headless: return "server.rack"
    case .server: return "externaldrive.connected.to.line.below"
    }
  }
}

struct DeviceInfoDTO: Codable {
  var alias: String
  var version: String
  var deviceModel: String?
  var deviceType: String?
  var fingerprint: String
  var port: Int?
  var protocolName: String?
  var download: Bool?

  enum CodingKeys: String, CodingKey {
    case alias
    case version
    case deviceModel
    case deviceType
    case fingerprint
    case port
    case download
    case protocolName = "protocol"
  }
}

struct MulticastAnnounce: Codable {
  var alias: String
  var version: String
  var deviceModel: String?
  var deviceType: String?
  var fingerprint: String
  var port: Int
  var protocolName: String
  var download: Bool
  var announcement: Bool

  enum CodingKeys: String, CodingKey {
    case alias
    case version
    case deviceModel
    case deviceType
    case fingerprint
    case port
    case download
    case announcement = "announce"
    case protocolName = "protocol"
  }
}

struct FileDTO: Codable, Equatable, Identifiable {
  var id: String
  var fileName: String
  var size: Int
  var fileType: String
  var sha256: String?
  var preview: String?
}

struct PrepareUploadRequest: Codable {
  var info: DeviceInfoDTO
  var files: [String: FileDTO]
}

struct PrepareUploadResponse: Codable {
  var sessionId: String
  var files: [String: String]
}

/// A device currently reachable on the local network.
struct Device: Identifiable, Equatable {
  /// Fingerprint — stable across restarts, so it doubles as the list identity.
  let id: String
  var alias: String
  var deviceType: DeviceType
  var host: String
  var port: Int
  var lastSeen: Date
  /// `http` or `https`, as announced by the peer.
  var protocolName: String = "http"

  var fingerprint: String { id }

  func baseURL(encrypted: Bool) -> URL? {
    URL(string: "\(encrypted ? "https" : "http")://\(host):\(port)")
  }
}

/// A pending upload request that needs the user's accept/decline decision.
struct IncomingRequest: Identifiable, Equatable {
  let id: String
  var peerAlias: String
  var files: [FileDTO]
}

/// A file the user picked for sending.
struct SelectedFile: Identifiable, Equatable {
  let id: String
  let url: URL
  let name: String
  let size: Int
  let fileType: String

  static func make(from url: URL) -> SelectedFile? {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
    if values?.isDirectory == true {
      return nil
    }
    let size = values?.fileSize ?? 0
    let type = values?.contentType?.preferredMIMEType ?? "application/octet-stream"
    return SelectedFile(id: UUID().uuidString, url: url, name: url.lastPathComponent, size: size, fileType: type)
  }
}

/// A file that finished downloading into the app's Documents folder.
struct ReceivedFile: Identifiable, Equatable {
  let id: String
  let name: String
  let url: URL
  let size: Int
  let date: Date
}

struct IncomingTransfer: Identifiable, Equatable {
  let id: String
  var peerAlias: String
  var fileNames: [String]
  var received: Int
  var total: Int
  var isFinished: Bool
}

struct OutgoingTransfer: Identifiable, Equatable {
  let id: String
  var deviceAlias: String
  var fileNames: [String]
  var completed: Int
  var total: Int
  var isFinished: Bool
  var error: String?
  var sessionId: String?
}
