import SwiftUI
import UIKit

struct AmbientBackground: View {
  var body: some View {
    Color(uiColor: .systemBackground).ignoresSafeArea()
  }
}

enum AppRadius {
  static let control: CGFloat = 22
}

extension Color {
  static let localSendAccent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.514, green: 0.839, blue: 0.788, alpha: 1)
      : UIColor(red: 0, green: 0.502, blue: 0.502, alpha: 1)
  })
}

extension View {
  @ViewBuilder
  func softTopScrollEdge() -> some View {
    if #available(iOS 26.0, *) {
      self.scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      self
    }
  }

  /// Liquid Glass on iOS 26+, thin material before that.
  @ViewBuilder
  func glassPanel(cornerRadius: CGFloat = AppRadius.control, interactive: Bool = false) -> some View {
    if #available(iOS 26.0, *) {
      self.glassEffect(
        interactive ? .regular.interactive() : .regular,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      self
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
        )
    }
  }
}

/// Card used for every grouped block of content.
struct GlassCard<Content: View>: View {
  var cornerRadius: CGFloat = AppRadius.control
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassPanel(cornerRadius: cornerRadius)
  }
}

/// Prominent glass button, used where LocalSend shows its primary action.
struct GlassProminentButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .padding(.horizontal, 22)
      .padding(.vertical, 14)
      .glassPanel(interactive: true)
      .saturation(configuration.isPressed ? 1.25 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
  }
}

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(LocalizedStringKey(title))
      .font(.headline)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension Int64 {
  var formattedSize: String {
    ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
  }
}
