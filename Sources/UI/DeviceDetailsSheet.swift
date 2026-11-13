import SwiftUI

/// Mirrors the Flutter "device details" page: identity of one peer plus the two actions
/// that matter from a device list (favourite toggle, start sending).
struct DeviceDetailsSheet: View {
  let device: Device
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private var favourite: FavoriteDevice {
    FavoriteDevice(
      fingerprint: device.fingerprint,
      alias: device.alias,
      host: device.host,
      port: device.port,
      deviceType: device.deviceType.rawValue,
      protocolName: device.protocolName
    )
  }

  private var isFavourite: Bool {
    model.favorites.isFavorite(device.fingerprint)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        VStack(spacing: 10) {
          Image(systemName: device.deviceType.symbolName)
            .font(.system(size: 34))
            .foregroundStyle(.tint)
            .frame(width: 88, height: 88)
            .glassPanel(cornerRadius: AppRadius.control)

          Text(device.alias)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)

          Text(device.deviceType.rawValue.capitalized)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)

        GlassCard {
          VStack(alignment: .leading, spacing: 12) {
            row("Address", "\(device.host):\(String(device.port))")
            row("Protocol", device.protocolName.uppercased())
            row("Fingerprint", device.fingerprint, monospaced: true)
          }
        }

        HStack(spacing: 12) {
          Button {
            model.favorites.toggle(favourite)
          } label: {
            Label(isFavourite ? "Remove favourite" : "Add favourite", systemImage: isFavourite ? "star.slash" : "star")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(GlassProminentButtonStyle())

          Button {
            dismiss()
            model.send(files: model.selection, to: device)
          } label: {
            Label("Send", systemImage: "paperplane.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(GlassProminentButtonStyle())
          .disabled(model.selection.isEmpty)
        }
      }
      .padding(20)
    }
    .background(AmbientBackground())
    .presentationDetents([.medium, .large])
  }

  private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
  }
}
