import SwiftUI

/// Ambient light behind everything: the glass panels need something to refract.
struct AmbientBackground: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      Color(colorScheme == .dark ? .black : .systemBackground)
      GeometryReader { proxy in
        ZStack {
          blob(.blue, size: proxy.size.width * 1.1)
            .offset(x: -proxy.size.width * 0.35, y: -proxy.size.height * 0.30)
          blob(.teal, size: proxy.size.width * 0.9)
            .offset(x: proxy.size.width * 0.45, y: -proxy.size.height * 0.05)
          blob(.indigo, size: proxy.size.width * 1.2)
            .offset(x: -proxy.size.width * 0.15, y: proxy.size.height * 0.45)
        }
        .blur(radius: 80)
      }
    }
    .ignoresSafeArea()
  }

  private func blob(_ color: Color, size: CGFloat) -> some View {
    Circle()
      .fill(color.opacity(colorScheme == .dark ? 0.35 : 0.22))
      .frame(width: size, height: size)
  }
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
  func glassPanel(cornerRadius: CGFloat = 26, interactive: Bool = false) -> some View {
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
  var cornerRadius: CGFloat = 26
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
      .glassPanel(cornerRadius: 22, interactive: true)
      .saturation(configuration.isPressed ? 1.25 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
  }
}

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.headline)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension Int64 {
  var formattedSize: String {
    ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
  }
}
