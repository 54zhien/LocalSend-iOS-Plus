import Foundation
import Observation
import UniformTypeIdentifiers

/// Thread-safe hand-off of the receive folder to the HTTP server, which writes off the main actor.
final class URLBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: URL?

  init(_ value: URL? = nil) {
    stored = value
  }

  func set(_ value: URL?) {
    lock.lock()
    stored = value
    lock.unlock()
  }

  var value: URL? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}

/// Remembers a user-picked receive folder across launches.
///
/// iOS only grants access to folders outside the sandbox through a security-scoped bookmark, so the
/// picker's URL cannot be stored as a plain path — the bookmark is what survives a restart.
@MainActor
@Observable
final class DestinationStore {
  private static let key = "destination.bookmark"

  private(set) var folderURL: URL?
  private(set) var displayName: String?
  private var scopedURL: URL?

  /// Mirrors the resolved folder for readers outside the main actor.
  let box = URLBox()

  init() {
    restore()
  }

  /// Default `Documents/LocalSend` when the user never picked a folder.
  var effectiveURL: URL {
    folderURL ?? LocalHTTPServer.downloadsDirectory()
  }

  func setFolder(_ url: URL) -> Bool {
    releaseScope()
    let bookmark: Data
    do {
      bookmark = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    } catch {
      return false
    }
    UserDefaults.standard.set(bookmark, forKey: Self.key)
    apply(url)
    return true
  }

  func clear() {
    releaseScope()
    UserDefaults.standard.removeObject(forKey: Self.key)
    folderURL = nil
    displayName = nil
    box.set(nil)
  }

  private func restore() {
    guard let bookmark = UserDefaults.standard.data(forKey: Self.key) else { return }
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    else {
      return
    }
    if stale, let refreshed = try? url.bookmarkData() {
      UserDefaults.standard.set(refreshed, forKey: Self.key)
    }
    apply(url)
  }

  private func apply(_ url: URL) {
    _ = url.startAccessingSecurityScopedResource()
    scopedURL = url
    folderURL = url
    displayName = url.lastPathComponent
    box.set(url)
  }

  private func releaseScope() {
    scopedURL?.stopAccessingSecurityScopedResource()
    scopedURL = nil
  }
}
