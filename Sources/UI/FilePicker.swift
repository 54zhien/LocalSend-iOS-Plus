import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Uses UIKit's document picker so multi-file confirmation is handled by Files.
struct FilePicker: UIViewControllerRepresentable {
  var contentTypes: [UTType] = [.item]
  var allowsMultipleSelection = true
  let onPick: ([URL]) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
    picker.allowsMultipleSelection = allowsMultipleSelection
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onPick: onPick, onCancel: onCancel)
  }

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
      self.onPick = onPick
      self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      onPick(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      onCancel()
    }
  }
}
