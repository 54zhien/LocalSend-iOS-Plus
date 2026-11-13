import Foundation
import UIKit

enum SelectionStaging {
  static func text(_ value: String) throws -> SelectedFile {
    try data(Data(value.utf8), name: "Text.txt", type: "text/plain")
  }

  static func clipboard() throws -> [SelectedFile] {
    if let value = UIPasteboard.general.string, !value.isEmpty {
      return [try text(value)]
    }
    if let image = UIPasteboard.general.image, let png = image.pngData() {
      return [try data(png, name: "Clipboard.png", type: "image/png")]
    }
    if let url = UIPasteboard.general.url, url.isFileURL, let file = SelectedFile.make(from: url) {
      return [file]
    }
    return []
  }

  static func files(in folder: URL) -> [SelectedFile] {
    let access = folder.startAccessingSecurityScopedResource()
    defer { if access { folder.stopAccessingSecurityScopedResource() } }
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let contents = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
    return contents.compactMap { item in
      guard let url = item as? URL,
        (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
      else { return nil }
      return SelectedFile.make(from: url)
    }
  }

  static func data(_ value: Data, name: String, type: String) throws -> SelectedFile {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalSendSelection", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(UUID().uuidString + "-" + name)
    try value.write(to: url, options: .atomic)
    return SelectedFile(id: UUID().uuidString, url: url, name: name, size: value.count, fileType: type)
  }
}
