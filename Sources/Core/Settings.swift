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
  /// Auto-accept only for devices marked as favourites (upstream "paired" quick save).
  var quickSaveFromFavorites: Bool { didSet { save() } }
  /// Close the receive screen as soon as the last file arrived.
  var autoFinish: Bool { didSet { save() } }
  /// Save received images/videos to the photo library in addition to Documents.
  var saveToPhotos: Bool { didSet { save() } }
  /// Advertise the download API (`/prepare-download`), used by browsers/web clients.
  var downloadEnabled: Bool { didSet { save() } }
  /// Seconds between two device scans.
  var scanInterval: Double { didSet { save() } }
  /// HTTPS + mutual TLS, like the Flutter default.
  var encryption: Bool { didSet { save() } }
  /// Optional PIN required by `prepare-upload` and `prepare-download`.
  var pin: String { didSet { save() } }
  /// Listening port (53317 by default).
  var port: Int { didSet { save() } }

  private struct Snapshot: Codable {
    var alias: String
    var quickSave: Bool
    var quickSaveFromFavorites: Bool?
    var autoFinish: Bool?
    var saveToPhotos: Bool
    var downloadEnabled: Bool
    var scanInterval: Double
    var encryption: Bool?
    var pin: String?
    var port: Int?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      alias = try container.decode(String.self, forKey: .alias)
      quickSave = try container.decode(Bool.self, forKey: .quickSave)
      quickSaveFromFavorites = try container.decodeIfPresent(Bool.self, forKey: .quickSaveFromFavorites)
      autoFinish = try container.decodeIfPresent(Bool.self, forKey: .autoFinish)
      saveToPhotos = try container.decode(Bool.self, forKey: .saveToPhotos)
      downloadEnabled = try container.decode(Bool.self, forKey: .downloadEnabled)
      scanInterval = try container.decode(Double.self, forKey: .scanInterval)
      encryption = try container.decodeIfPresent(Bool.self, forKey: .encryption)
      pin = try container.decodeIfPresent(String.self, forKey: .pin)
      port = try container.decodeIfPresent(Int.self, forKey: .port)
    }

    init(
      alias: String,
      quickSave: Bool,
      quickSaveFromFavorites: Bool,
      autoFinish: Bool,
      saveToPhotos: Bool,
      downloadEnabled: Bool,
      scanInterval: Double,
      encryption: Bool,
      pin: String,
      port: Int
    ) {
      self.alias = alias
      self.quickSave = quickSave
      self.quickSaveFromFavorites = quickSaveFromFavorites
      self.autoFinish = autoFinish
      self.saveToPhotos = saveToPhotos
      self.downloadEnabled = downloadEnabled
      self.scanInterval = scanInterval
      self.encryption = encryption
      self.pin = pin
      self.port = port
    }
  }

  init() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: "settings"),
      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
    {
      alias = snapshot.alias
      quickSave = snapshot.quickSave
      quickSaveFromFavorites = snapshot.quickSaveFromFavorites ?? false
      autoFinish = snapshot.autoFinish ?? false
      saveToPhotos = snapshot.saveToPhotos
      downloadEnabled = snapshot.downloadEnabled
      scanInterval = snapshot.scanInterval
      encryption = snapshot.encryption ?? true
      pin = snapshot.pin ?? ""
      port = snapshot.port ?? 53317
    } else {
      alias = UIDevice.current.name
      quickSave = true
      quickSaveFromFavorites = false
      autoFinish = false
      saveToPhotos = false
      downloadEnabled = false
      scanInterval = 12
      encryption = true
      pin = ""
      port = 53317
    }
  }

  func save() {
    let snapshot = Snapshot(
      alias: alias,
      quickSave: quickSave,
      quickSaveFromFavorites: quickSaveFromFavorites,
      autoFinish: autoFinish,
      saveToPhotos: saveToPhotos,
      downloadEnabled: downloadEnabled,
      scanInterval: scanInterval,
      encryption: encryption,
      pin: pin,
      port: port
    )
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.standard.set(data, forKey: "settings")
    UserDefaults.standard.set(alias, forKey: "alias")
  }
}
