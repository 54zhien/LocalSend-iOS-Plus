import SwiftUI
import UIKit

extension AppSettings {
  var preferredColorScheme: ColorScheme? {
    if colorMode == .oled { return .dark }
    switch brightness {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  var selectedLocale: Locale {
    languageCode == "system" ? .autoupdatingCurrent : Locale(identifier: languageCode)
  }

  var accentColor: Color {
    switch colorMode {
    case .localsend, .oled: .localSendAccent
    case .yaru: Color(red: 233 / 255, green: 84 / 255, blue: 32 / 255)
    case .custom: Color(hexRGB: customColorHex)
    }
  }
}

extension Color {
  init(hexRGB: String) {
    let value = Int(hexRGB, radix: 16) ?? 0x008F89
    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }

  var hexRGB: String {
    let color = UIColor(self)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "008F89" }
    return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
  }
}
