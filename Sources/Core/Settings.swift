import Foundation
import Observation
import UIKit

/// User settings, persisted to `UserDefaults` as one JSON snapshot.
@MainActor
@Observable
final class AppSettings {
  var alias: String { didSet { save() } }
  /// Accept incoming transfers without asking (the "quick save" mode of LocalSend).
  var quickSave: Bool { didSet { save() } }
  /// Save received images/videos to the photo library in addition to Documents.
  var saveToPhotos: Bool { didSet { save() } }
  /// Advertise the download API (`/prepare-download`), used by browsers/web clients.
  var downloadEnabled: Bool { didSet { save() } }
  /// Seconds between two device scans.
  var scanInterval: Double { didSet { save() } }

  private struct Snapshot: Codable {
    var alias: String
    var quickSave: Bool
    var saveToPhotos: Bool
    var downloadEnabled: Bool
    var scanInterval: Double
  }

  init() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: "settings"),
      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
    {
      alias = snapshot.alias
      quickSave = snapshot.quickSave
      saveToPhotos = snapshot.saveToPhotos
      downloadEnabled = snapshot.downloadEnabled
      scanInterval = snapshot.scanInterval
    } else {
      alias = UIDevice.current.name
      quickSave = true
      saveToPhotos = false
      downloadEnabled = false
      scanInterval = 12
    }
  }

  func save() {
    let snapshot = Snapshot(
      alias: alias,
      quickSave: quickSave,
      saveToPhotos: saveToPhotos,
      downloadEnabled: downloadEnabled,
      scanInterval: scanInterval
    )
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.standard.set(data, forKey: "settings")
    UserDefaults.standard.set(alias, forKey: "alias")
  }
}
