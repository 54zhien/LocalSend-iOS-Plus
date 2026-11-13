import Foundation
import Observation

struct FavoriteDevice: Codable, Identifiable, Hashable {
  var id: String { fingerprint }
  var fingerprint: String
  var alias: String
  var host: String
  var port: Int = 53317
  var deviceType: String?
  var protocolName: String = "https"
}

/// Favourites that survive restarts. Mirrors the Flutter `favoritesProvider`,
/// including the ability to add a peer by address when it is not discoverable.
@MainActor
@Observable
final class FavoritesStore {
  private static let key = "favorites.v1"

  private(set) var devices: [FavoriteDevice] = []

  init() {
    load()
  }

  func isFavorite(_ fingerprint: String) -> Bool {
    devices.contains { $0.fingerprint == fingerprint }
  }

  func toggle(_ device: FavoriteDevice) {
    if isFavorite(device.fingerprint) {
      remove(fingerprint: device.fingerprint)
    } else {
      devices.append(device)
      save()
    }
  }

  func add(alias: String, host: String, port: Int = 53317) {
    let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !host.isEmpty else { return }
    let existing = devices.firstIndex { $0.host == host && $0.port == port }
    let device = FavoriteDevice(
      fingerprint: "manual:\(host):\(port)",
      alias: trimmed,
      host: host,
      port: port
    )
    if let existing {
      devices[existing] = device
    } else {
      devices.append(device)
    }
    save()
  }

  func rename(_ device: FavoriteDevice, alias: String) {
    guard let index = devices.firstIndex(where: { $0.fingerprint == device.fingerprint }) else { return }
    devices[index].alias = alias
    save()
  }

  func remove(fingerprint: String) {
    devices.removeAll { $0.fingerprint == fingerprint }
    save()
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Self.key),
      let decoded = try? JSONDecoder().decode([FavoriteDevice].self, from: data)
    else { return }
    devices = decoded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(devices) else { return }
    UserDefaults.standard.set(data, forKey: Self.key)
  }
}
