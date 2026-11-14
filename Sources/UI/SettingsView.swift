import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Bindable var settings: AppSettings
  @State private var choosingFolder = false

  @State private var aliasDraft = ""
  @State private var pinDraft = ""
  @State private var portDraft = ""
  @State private var deviceModelDraft = ""
  @State private var pinEditing = false
  @State private var showingLanguages = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          settingsSection("General") { generalCard }
          settingsSection("Receive") { transfersCard }
          if settings.advanced { settingsSection("Send") { sendCard } }
          settingsSection("Network") { deviceCard }
          settingsSection("Other") { aboutCard }
          toggleRow("Advanced settings", isOn: $settings.advanced)
            .padding(.horizontal, 12)
          VStack(spacing: 10) {
            Image("LocalSendLogo")
              .resizable()
              .renderingMode(.template)
              .foregroundStyle(.tint)
              .frame(width: 140, height: 140)
            Text("LocalSend").font(.largeTitle.weight(.semibold))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 45)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
      }
      .softTopScrollEdge()
      .background(AmbientBackground())
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
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
        pinEditing = !settings.pin.isEmpty
        portDraft = String(settings.port)
        deviceModelDraft = settings.deviceModel
      }
      .sheet(isPresented: $showingLanguages) {
        LanguagePickerView(settings: settings)
      }
    }
  }

  private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: title)
        .padding(.horizontal, 12)
      content()
    }
  }

  private var generalCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
          Text("Theme").frame(maxWidth: .infinity, alignment: .leading)
          Picker("Theme", selection: $settings.brightness) {
            Text("Follow system").tag(AppBrightness.system)
            Text("Light").tag(AppBrightness.light)
            Text("Dark").tag(AppBrightness.dark)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 146, height: 46)
          .materialControl()
        }
        HStack(spacing: 12) {
          Text("Color").frame(maxWidth: .infinity, alignment: .leading)
          Picker("Color", selection: $settings.colorMode) {
            Text("LocalSend").tag(AppColorMode.localsend)
            Text("OLED").tag(AppColorMode.oled)
            Text("Yaru").tag(AppColorMode.yaru)
            Text("Custom").tag(AppColorMode.custom)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 146, height: 46)
          .materialControl()
        }
        if settings.colorMode == .custom {
          HStack(spacing: 12) {
            Text("Custom color").frame(maxWidth: .infinity, alignment: .leading)
            ColorPicker("Custom color", selection: Binding(
              get: { Color(hexRGB: settings.customColorHex) },
              set: { settings.customColorHex = $0.hexRGB }
            ))
            .labelsHidden()
            .frame(width: 146, height: 46)
            .materialControl()
          }
        }
        HStack(spacing: 12) {
          Text("Language").frame(maxWidth: .infinity, alignment: .leading)
          Button {
            showingLanguages = true
          } label: {
            Group {
              if settings.languageCode == "system" {
                Text("Follow system")
              } else {
                Text(Locale(identifier: settings.languageCode).localizedString(forIdentifier: settings.languageCode) ?? settings.languageCode)
              }
            }
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(width: 146, height: 46)
              .materialControl()
          }
          .buttonStyle(.plain)
        }
        toggleRow("Animations", isOn: $settings.animations)
      }
    }
  }

  private func settingsValue(_ title: String, _ value: String) -> some View {
    HStack(spacing: 12) {
      Text(LocalizedStringKey(title))
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(LocalizedStringKey(value))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: 146)
        .frame(minHeight: 46)
        .materialControl()
    }
    .font(.subheadline)
  }

  private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
    HStack(spacing: 12) {
      Text(LocalizedStringKey(title))
        .frame(maxWidth: .infinity, alignment: .leading)
      Toggle(LocalizedStringKey(title), isOn: isOn)
        .labelsHidden()
        .frame(width: 146, height: 46)
    }
    .font(.subheadline)
  }

  private var deviceCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 16) {
        if settings.encryption && model.identity.identity == nil {
          Text("TLS identity unavailable. The server is using HTTP.")
            .font(.footnote)
            .foregroundStyle(.orange)
        }
        HStack(spacing: 12) {
          Text(LocalizedStringKey(model.serverRunning ? "Server" : "Server (offline)"))
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
          HStack(spacing: 28) {
            Button {
              if model.serverRunning { model.applyNetworkSettings() }
              else { model.start() }
            } label: {
              Image(systemName: model.serverRunning ? "arrow.clockwise" : "play.fill")
            }
            .accessibilityLabel(model.serverRunning ? "Restart" : "Start")
            Button { model.stop() } label: { Image(systemName: "stop.fill") }
              .disabled(!model.serverRunning)
              .accessibilityLabel("Stop")
          }
          .frame(width: 146, height: 46)
          .materialControl()
        }

        HStack(spacing: 12) {
          Text("Device name")
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
          HStack(spacing: 4) {
            TextField("Device name", text: $aliasDraft)
              .textFieldStyle(.plain)
              .submitLabel(.done)
              .onSubmit { applyAlias() }
            Button { applyAlias() } label: { Image(systemName: "checkmark") }
              .disabled(aliasDraft == settings.alias)
          }
          .padding(12)
          .frame(width: 146)
          .materialControl()
        }

        if settings.advanced {
          HStack(spacing: 12) {
            Text("Device type").frame(maxWidth: .infinity, alignment: .leading)
            Picker("Device type", selection: $settings.deviceType) {
              ForEach(DeviceType.allCases, id: \.self) { type in
                Text(LocalizedStringKey(type.rawValue.capitalized)).tag(type)
              }
            }
            .labelsHidden()
            .frame(width: 146, height: 46)
            .materialControl()
            .onChange(of: settings.deviceType) { model.applyNetworkSettings() }
          }
          HStack(spacing: 12) {
            Text("Device model").frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
              TextField("Device model", text: $deviceModelDraft)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { applyDeviceModel() }
              Button { applyDeviceModel() } label: { Image(systemName: "checkmark") }
                .disabled(deviceModelDraft == settings.deviceModel)
            }
            .padding(12)
            .frame(width: 146)
            .materialControl()
          }
        }

        if settings.advanced {
          HStack(spacing: 12) {
          Text("Port")
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
          HStack(spacing: 4) {
            TextField("Port", text: $portDraft)
              .textFieldStyle(.plain)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.center)
            Button { applyPort() } label: { Image(systemName: "checkmark") }
              .disabled(portDraft == String(settings.port))
          }
          .padding(12)
          .frame(width: 146)
          .materialControl()
          }

          HStack(spacing: 12) {
          Text("Scan interval")
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
          Picker("Scan interval", selection: $settings.scanInterval) {
            ForEach(Array(stride(from: 4, through: 60, by: 4)), id: \.self) { seconds in
              Text("\(seconds) s").tag(Double(seconds))
            }
          }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 146, height: 46)
            .materialControl()
            .onChange(of: settings.scanInterval) {
              model.discovery.restart(interval: settings.scanInterval, timeout: settings.discoveryTimeout)
            }
          }

          HStack(spacing: 12) {
            Text("Discovery timeout").frame(maxWidth: .infinity, alignment: .leading)
            Picker("Discovery timeout", selection: $settings.discoveryTimeout) {
              ForEach([0.5, 0.9, 1.5, 3.0, 5.0], id: \.self) { seconds in
                Text("\(seconds.formatted()) s").tag(seconds)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 146, height: 46)
            .materialControl()
            .onChange(of: settings.discoveryTimeout) {
              model.discovery.restart(interval: settings.scanInterval, timeout: settings.discoveryTimeout)
            }
          }

          toggleRow("Encryption", isOn: $settings.encryption)
            .onChange(of: settings.encryption) { _, _ in
              model.applyNetworkSettings()
            }
        }

        Button {
          Task { await model.discovery.scan() }
        } label: {
          Label("Scan now", systemImage: "arrow.triangle.2.circlepath")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func applyPort() {
    guard let port = Int(portDraft), (1024...65535).contains(port) else {
      portDraft = String(settings.port)
      return
    }
    settings.port = port
    model.applyNetworkSettings()
  }

  private func applyAlias() {
    model.updateAlias(aliasDraft)
    aliasDraft = settings.alias
  }

  private func applyDeviceModel() {
    let value = deviceModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { deviceModelDraft = settings.deviceModel; return }
    settings.deviceModel = value
    model.applyNetworkSettings()
  }

  private var transfersCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 16) {
        toggleRow("Quick save", isOn: $settings.quickSave)
        toggleRow("Auto save from favourites", isOn: $settings.quickSaveFromFavorites)
        toggleRow("Require PIN", isOn: Binding(
          get: { pinEditing },
          set: { enabled in
            pinEditing = enabled
            if enabled {
              pinDraft = settings.pin
            } else {
              settings.pin = ""
              pinDraft = ""
              model.applyNetworkSettings()
            }
          }
        ))
        if pinEditing {
          HStack(spacing: 12) {
            Text("PIN")
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
              TextField("PIN", text: $pinDraft)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
              Button { applyPin() } label: { Image(systemName: "checkmark") }
                .disabled(pinDraft == settings.pin)
            }
            .padding(12)
            .frame(width: 146)
            .materialControl()
          }
        }
        toggleRow("Save media to Photos", isOn: $settings.saveToPhotos)
        toggleRow("Auto finish", isOn: $settings.autoFinish)
        toggleRow("Save to history", isOn: $settings.saveHistory)
        if settings.advanced {
          toggleRow("Verify checksums", isOn: $settings.verifyChecksums)
            .onChange(of: settings.verifyChecksums) { model.applyNetworkSettings() }
        }
        HStack(spacing: 12) {
          Text("Receive folder")
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button(model.destination.displayName ?? String(localized: "Choose")) { choosingFolder = true }
            .font(.subheadline)
            .lineLimit(1)
            .frame(width: 146, height: 46)
            .materialControl()
        }
      }
    }
  }

  private func applyPin() {
    let value = pinDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    settings.pin = value
    pinDraft = value
    model.applyNetworkSettings()
  }

  private var sendCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 16) {
        toggleRow("Auto accept link requests", isOn: $settings.shareViaLinkAutoAccept)
          .onChange(of: settings.shareViaLinkAutoAccept) { model.applyNetworkSettings() }
        toggleRow("Web download page", isOn: $settings.downloadEnabled)
          .onChange(of: settings.downloadEnabled) {
            model.applyNetworkSettings()
          }
        toggleRow("Create checksums", isOn: $settings.createChecksums)
      }
    }
  }

  private var aboutCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("App")
          Spacer()
          Text("LocalSend Plus").foregroundStyle(.secondary)
        }
        .font(.subheadline)
        HStack {
          Text("Protocol")
          Spacer()
          Text("v2.2 · \(model.deviceIdentity.protocolName.uppercased())").foregroundStyle(.secondary)
        }
        .font(.subheadline)
        HStack {
          Text("Devices seen")
          Spacer()
          Text(String(model.discovery.devices.count)).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        Link("Support LocalSend", destination: URL(string: "https://localsend.org")!)
        Link("Privacy policy", destination: URL(string: "https://localsend.org/privacy")!)
        Link("Terms of use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
      }
    }
  }

}

