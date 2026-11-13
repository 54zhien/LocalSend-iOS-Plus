import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MediaPicker: UIViewControllerRepresentable {
  let onPick: ([URL]) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .any(of: [.images, .videos])
    configuration.selectionLimit = 0
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
      self.onPick = onPick
      self.onCancel = onCancel
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard !results.isEmpty else { onCancel(); return }
      let group = DispatchGroup()
      let lock = NSLock()
      var copied: [Int: URL] = [:]
      for (index, result) in results.enumerated() {
        let provider = result.itemProvider
        let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
          ? UTType.movie.identifier : UTType.image.identifier
        group.enter()
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
          defer { group.leave() }
          guard let url else { return }
          let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
          do {
            try FileManager.default.copyItem(at: url, to: destination)
            lock.lock()
            copied[index] = destination
            lock.unlock()
          } catch { return }
        }
      }
      group.notify(queue: .main) {
        self.onPick(copied.sorted { $0.key < $1.key }.map(\.value))
      }
    }
  }
}
