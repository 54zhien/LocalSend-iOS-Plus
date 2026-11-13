import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point: stages the picked items in the App Group inbox and asks
/// the app to come forward, which then continues in the normal Send flow.
final class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    handle()
  }

  private func handle() {
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let providers = items.flatMap { $0.attachments ?? [] }

    guard !providers.isEmpty else {
      finish()
      return
    }

    let group = DispatchGroup()
    for provider in providers {
      group.enter()
      load(provider) { url in
        if let url {
          ShareInbox.stage(url)
        }
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in
      self?.finish()
    }
  }

  private func load(_ provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        if let url = item as? URL {
          completion(url)
          return
        }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
          completion(url)
          return
        }
        completion(nil)
      }
      return
    }

    let type = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
    provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
      guard let url else {
        completion(nil)
        return
      }
      let temp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
      try? FileManager.default.removeItem(at: temp)
      do {
        try FileManager.default.copyItem(at: url, to: temp)
        completion(temp)
      } catch {
        completion(nil)
      }
    }
  }

  private func finish() {
    if let url = URL(string: "\(ShareInbox.scheme)://share") {
      extensionContext?.open(url, completionHandler: nil)
    }
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
