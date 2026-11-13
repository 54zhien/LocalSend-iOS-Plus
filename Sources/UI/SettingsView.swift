import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Bindable var settings: AppSettings

  @State private var aliasDraft = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          deviceCard
          transfersCard
          discoveryCard
          aboutCard
        }
        .padding(16)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .navigationTitle("Settings")
      .onAppear { aliasDraft = model.identity.alias }
      .onChange(of: model.settings.downloadEnabled) { _, _ in
        model.refreshIdentity()
      }
    }
  }

  private var deviceCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Device")
        TextField("Device name", text: $aliasDraft)
          .textFieldStyle(.plain)
          .font(.body.weight(.medium))
          .submitLabel(.done)
          .onSubmit { model.updateAlias(aliasDraft) }
          .padding(12)
          .glassPanel(cornerRadius: 14)
        HStack {
          Text("Fingerprint")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
          Text(model.identity.fingerprint.prefix(16) + "…")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var transfersCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "Transfers")
        Toggle(isOn: $settings.quickSave) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Quick save").font(.subheadline.weight(.medium))
            Text("Accept incoming files without asking.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Divider().opacity(0.4)
        Toggle(isOn: $settings.saveToPhotos) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Save photos to library").font(.subheadline.weight(.medium))
            Text("Also import received images into Photos.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Divider().opacity(0.4)
        Toggle(isOn: $settings.downloadEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Allow web downloads").font(.subheadline.weight(.medium))
            Text("Advertise the download API to browsers.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var discoveryCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Discovery")
        Stepper(
          value: Binding(
            get: { settings.scanInterval },
            set: { value in
              settings.scanInterval = value
              model.discovery.restart(interval: value)
            }
          ),
          in: 4...60,
          step: 4
        ) {
          Text("Scan every \(Int(settings.scanInterval))s")
            .font(.subheadline.weight(.medium))
        }
        Button {
          Task { await model.discovery.scan() }
        } label: {
          Label("Scan now", systemImage: "antenna.radiowaves.left.and.right")
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(GlassProminentButtonStyle())
        if let lastScan = model.discovery.lastScan {
          Text("Last scan \(lastScan.formatted(date: .omitted, time: .standard))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var aboutCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "About")
        row("App", "LocalSend (SwiftUI)")
        row("Protocol", "v2.2 · HTTP")
        row("Port", "\(model.identity.port)")
        row("Devices seen", "\(model.discovery.devices.count)")
      }
    }
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.subheadline.weight(.medium))
    }
  }
}
