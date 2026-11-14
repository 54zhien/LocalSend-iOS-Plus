import CryptoKit
import Foundation

enum FileHash {
  static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hash.update(data: chunk)
    }
    return Hex.encode(Data(hash.finalize()))
  }
}
