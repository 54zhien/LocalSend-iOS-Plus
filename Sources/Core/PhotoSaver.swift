import Foundation
import Photos
import UniformTypeIdentifiers

/// Saves received media into the photo library, mirroring the Flutter
/// "save to photos" option (only images and videos are eligible).
enum PhotoSaver {
  static func isMedia(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
    return type.conforms(to: .image) || type.conforms(to: .movie)
  }

  /// Returns how many files were imported.
  @discardableResult
  static func save(_ urls: [URL]) async -> Int {
    let candidates = urls.filter { isMedia($0) && FileManager.default.fileExists(atPath: $0.path) }
    guard !candidates.isEmpty else { return 0 }

    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { return 0 }

    var saved = 0
    for url in candidates {
      let type = UTType(filenameExtension: url.pathExtension.lowercased())
      let isVideo = type?.conforms(to: .movie) ?? false
      do {
        try await PHPhotoLibrary.shared().performChanges {
          if isVideo {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
          } else {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
          }
        }
        saved += 1
      } catch {
        continue
      }
    }
    return saved
  }
}
