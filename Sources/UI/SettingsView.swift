import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Bindable var settings: AppSettings
  @State private var choosingFolder = false

  @State private var aliasDraft = ""
  @State private var pinDraft = ""
  @State private var portDraft = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          deviceCard
          transfersCard
          discoveryCard
          aboutCard
        }
        .padding(20)
      }
      .softTopScrollEdge()
      .background(AmbientBackground())
      .navigationTitle("Settings")
      .fileImporter(
        isPresented: $choosingFolder,
        allowedContentTypes: [.folder],
        allowsMultipleSelection: false
      ) { result in
        guard case let .success(urls) = result, let url = urls.first else { return }
        _ = model.destination.setFolder(url)
      }
      .onAppear {
        aliasDraft = settings.alias
        pinDraft = settings.pin
        portDraft = String(settings.port)
      }
    }
  }

  private var deviceCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Device")

        HStack {
          TextField("Device name", text: $aliasDraft)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .onSubmit {
              model.updateAlias(aliasDraft)
              aliasDraft = model.settings.alias
            }
          Button("Save") {
            model.updateAlias(aliasDraft)
            aliasDraft = model.settings.alias
          }
          .font(.footnote.weight(.semibold))
          .disabled(aliasDraft == settings.alias)
        }

        Toggle("Encryption (HTTPS + mTLS)", isOn: $settings.encryption)
          .onChange(of: settings.encryption) { _, _ in
            model.applyNetworkSettings()
          }
        Toggle("Require PIN", isOn: Binding(
          get: { !settings.pin.isEmpty },
          set: { enabled in
            if !enabled {
              settings.pin = ""
              pinDraft = ""
              model.applyNetworkSettings()
            }
          }
        ))

        HStack {
          TextField("PIN (empty turns it off)", text: $pinDraft)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numberPad)
          Button("Save") {
            settings.pin = pinDraft
            model.applyNetworkSettings()
          }
          .font(.footnote.weight(.semibold))
          .disabled(pinDraft == settings.pin)
        }

        HStack {
          TextField("Port", text: $portDraft)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numberPad)
            .frame(maxWidth: 120)
          Button("Apply") {
            if let port = Int(portDraft), (1024...65535).contains(port) {
              settings.port = port
              model.applyNetworkSettings()
            } else {
              portDraft = String(settings.port)
            }
          }
          .font(.footnote.weight(.semibold))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Fingerprint")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(model.identity.fingerprint)
            .font(.system(.caption2, design: .monospaced))
            .textSelection(.enabled)
        }
      }
    }
  }

  private var transfersCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Transfers")
        Picker("Quick save", selection: quickSaveMode) {
          Text("Off").tag(QuickSaveMode.off)
          Text("Always").tag(QuickSaveMode.always)
          Text("Favourites only").tag(QuickSaveMode.favourites)
        }
        .pickerStyle(.segmented)
        Text(quickSaveHint)
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Auto finish", isOn: $settings.autoFinish)
        Text("Leave the transfer screen as soon as the last file is written.")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Receive folder")
            Text(model.destination.displayName ?? "Default: Documents/LocalSend Plus")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 12)
          Button("Choose") { choosingFolder = true }
            .buttonStyle(.borderless)
          if model.destination.folderURL != nil {
            Button("Reset") { model.destination.clear() }
              .buttonStyle(.borderless)
          }
        }
        Toggle("Save media to Photos", isOn: $settings.saveToPhotos)
        Toggle("Web download page", isOn: $settings.downloadEnabled)
          .onChange(of: settings.downloadEnabled) {
            model.applyNetworkSettings()
          }
      }
    }
  }

  private var discoveryCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Discovery")
        Stepper(
          "Scan every \(Int(settings.scanInterval))s",
          value: $settings.scanInterval,
          in: 4...60,
          step: 4
        )
        .onChange(of: settings.scanInterval) {
          model.discovery.restart(interval: settings.scanInterval)
        }

        HStack {
          Button {
            Task { await model.discovery.scan() }
          } label: {
            Label("Scan now", systemImage: "arrow.triangle.2.circlepath")
          }
          .buttonStyle(GlassProminentButtonStyle())

          Spacer(minLength: 0)

          if let last = model.discovery.lastScan {
            Text(last.formatted(date: .omitted, time: .shortened))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var aboutCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeader(title: "About")
        HStack {
          Text("App")
          Spacer()
          Text("LocalSend Plus").foregroundStyle(.secondary)
        }
        .font(.subheadline)
        HStack {
          Text("Protocol")
          Spacer()
          Text("v2.2 · \(settings.encryption ? "HTTPS" : "HTTP")").foregroundStyle(.secondary)
        }
        .font(.subheadline)
        HStack {
          Text("Devices seen")
          Spacer()
          Text(String(model.discovery.devices.count)).foregroundStyle(.secondary)
        }
        .font(.subheadline)
      }
    }
  }

  /// The upstream client exposes quick save as three modes; two booleans model them here.
  private enum QuickSaveMode: Hashable {
    case off
    case always
    case favourites
  }

  private var quickSaveMode: Binding<QuickSaveMode> {
    Binding(
      get: {
        if settings.quickSave { return .always }
        if settings.quickSaveFromFavorites { return .favourites }
        return .off
      },
      set: { mode in
        settings.quickSave = mode == .always
        settings.quickSaveFromFavorites = mode == .favourites
      }
    )
  }

  private var quickSaveHint: String {
    switch quickSaveMode.wrappedValue {
    case .off: "Every incoming transfer asks for confirmation."
    case .always: "Incoming transfers are accepted without asking."
    case .favourites: "Only devices you marked as favourites are accepted automatically."
    }
  }
}

