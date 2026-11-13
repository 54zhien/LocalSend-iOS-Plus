import Foundation

/// Files handed over by the Share Extension, staged in the App Group container.
///
/// The extension cannot talk to the app directly, so it copies each picked item into
/// `Inbox/` and appends a line to `pending.json`; the app drains that queue on launch and
/// whenever it is opened through `localsendnative://share`.
enum ShareInbox {
  static let appGroup = "group.org.localsend.native"
  static let scheme = "localsendnative"

  struct Item: Codable, Identifiable {
    var id: String = UUID().uuidString
    var fileName: String
  }

  private static var directory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
  }

  static var inboxURL: URL? {
    directory?.appendingPathComponent("Inbox", isDirectory: true)
  }

  private static var manifestURL: URL? {
    directory?.appendingPathComponent("pending.json")
  }

  /// Copies a staged file into `Inbox` and records it. Called by the extension.
  @discardableResult
  static func stage(_ source: URL) -> Item? {
    guard let inbox = inboxURL else { return nil }
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

    let name = source.lastPathComponent.isEmpty ? UUID().uuidString : source.lastPathComponent
    let unique = (inbox.appendingPathComponent(name))
    var target = unique
    var index = 1
    while FileManager.default.fileExists(atPath: target.path) {
      let base = (name as NSString).deletingPathExtension
      let ext = (name as NSString).pathExtension
      let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
      target = inbox.appendingPathComponent(candidate)
      index += 1
    }

    do {
      try FileManager.default.copyItem(at: source, to: target)
    } catch {
      return nil
    }

    let item = Item(fileName: target.lastPathComponent)
    append(item)
    return item
  }

  private static func append(_ item: Item) {
    guard let manifestURL else { return }
    var items = pending()
    items.append(item)
    if let data = try? JSONEncoder().encode(items) {
      try? data.write(to: manifestURL, options: .atomic)
    }
  }

  static func pending() -> [Item] {
    guard let manifestURL, let data = try? Data(contentsOf: manifestURL),
      let items = try? JSONDecoder().decode([Item].self, from: data)
    else { return [] }
    return items
  }

  /// Removes the queued items from the inbox and returns their URLs.
  static func drain() -> [URL] {
    guard let inbox = inboxURL else { return [] }
    let items = pending()
    var urls: [URL] = []
    for item in items {
      let url = inbox.appendingPathComponent(item.fileName)
      if FileManager.default.fileExists(atPath: url.path) {
        urls.append(url)
      }
    }
    if let manifestURL {
      try? FileManager.default.removeItem(at: manifestURL)
    }
    return urls
  }
}
