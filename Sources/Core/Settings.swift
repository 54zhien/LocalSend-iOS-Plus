import Foundation
import Observation
import UIKit

enum AppBrightness: String, CaseIterable, Codable {
  case system, light, dark
}

enum AppColorMode: String, CaseIterable, Codable {
  case localsend, oled, yaru, custom
}

enum AppSendMode: String, CaseIterable, Codable {
  case single, multiple
}

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
  var animations: Bool { didSet { save() } }
  var brightness: AppBrightness { didSet { save() } }
  var colorMode: AppColorMode { didSet { save() } }
  var customColorHex: String { didSet { save() } }
  var languageCode: String { didSet { save() } }
  var advanced: Bool { didSet { save() } }
  var sendMode: AppSendMode { didSet { save() } }

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
    var animations: Bool?
    var brightness: AppBrightness?
    var colorMode: AppColorMode?
    var customColorHex: String?
    var languageCode: String?
    var advanced: Bool?
    var sendMode: AppSendMode?

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
      animations = try container.decodeIfPresent(Bool.self, forKey: .animations)
      brightness = try container.decodeIfPresent(AppBrightness.self, forKey: .brightness)
      colorMode = try container.decodeIfPresent(AppColorMode.self, forKey: .colorMode)
      customColorHex = try container.decodeIfPresent(String.self, forKey: .customColorHex)
      languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
      advanced = try container.decodeIfPresent(Bool.self, forKey: .advanced)
      sendMode = try container.decodeIfPresent(AppSendMode.self, forKey: .sendMode)
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
      port: Int,
      animations: Bool,
      brightness: AppBrightness,
      colorMode: AppColorMode,
      customColorHex: String,
      languageCode: String,
      advanced: Bool,
      sendMode: AppSendMode
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
      self.animations = animations
      self.brightness = brightness
      self.colorMode = colorMode
      self.customColorHex = customColorHex
      self.languageCode = languageCode
      self.advanced = advanced
      self.sendMode = sendMode
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
      animations = snapshot.animations ?? true
      brightness = snapshot.brightness ?? .system
      colorMode = snapshot.colorMode ?? .localsend
      customColorHex = snapshot.customColorHex ?? "008F89"
      languageCode = snapshot.languageCode ?? "system"
      advanced = snapshot.advanced ?? false
      sendMode = snapshot.sendMode ?? .single
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
      animations = true
      brightness = .system
      colorMode = .localsend
      customColorHex = "008F89"
      languageCode = "system"
      advanced = false
      sendMode = .single
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
      port: port,
      animations: animations,
      brightness: brightness,
      colorMode: colorMode,
      customColorHex: customColorHex,
      languageCode: languageCode,
      advanced: advanced,
      sendMode: sendMode
    )
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.standard.set(data, forKey: "settings")
    UserDefaults.standard.set(alias, forKey: "alias")
  }
}
