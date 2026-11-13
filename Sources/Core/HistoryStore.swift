import Foundation
import Observation

struct HistoryFile: Codable, Identifiable, Hashable {
  var id: String = UUID().uuidString
  var name: String
  var size: Int64
  /// Relative path inside `Documents/LocalSend` for received files.
  var relativePath: String?
}

struct HistoryEntry: Codable, Identifiable, Hashable {
  enum Direction: String, Codable {
    case sent
    case received
  }

  var id: String = UUID().uuidString
  var direction: Direction
  var alias: String
  var files: [HistoryFile]
  var date: Date = Date()

  var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// Persisted transfer history, replacing the Flutter `receiveHistoryProvider`.
@MainActor
@Observable
final class HistoryStore {
  private static let key = "history.v1"

  private(set) var entries: [HistoryEntry] = []

  init() {
    load()
  }

  func add(_ entry: HistoryEntry) {
    entries.insert(entry, at: 0)
    if entries.count > 200 { entries.removeLast(entries.count - 200) }
    save()
  }

  func add(direction: HistoryEntry.Direction, alias: String, files: [HistoryFile]) {
    guard !files.isEmpty else { return }
    add(HistoryEntry(direction: direction, alias: alias, files: files))
  }

  func clear() {
    entries.removeAll()
    save()
  }

  func remove(_ entry: HistoryEntry) {
    entries.removeAll { $0.id == entry.id }
    save()
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Self.key),
      let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
    else { return }
    entries = decoded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: Self.key)
  }
}
