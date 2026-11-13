import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
  @Environment(AppModel.self) private var model

  @State private var importerPresented = false
  @State private var folderPickerPresented = false
  @State private var mediaPickerPresented = false
  @State private var textSheetPresented = false
  @State private var textDraft = ""
  @State private var favoriteSheetPresented = false
  @State private var scannerPresented = false
  @State private var detailsDevice: Device?

  var body: some View {
    @Bindable var model = model

    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          selectionCard(model: model)
          if !model.favorites.devices.isEmpty { favoritesCard }
          devicesCard
        }
        .padding(15)
      }
      .softTopScrollEdge()
      .background(AmbientBackground())
      .navigationTitle("Send")
      .toolbar(.hidden, for: .navigationBar)
      .refreshable { await model.discovery.scan() }
      .sheet(isPresented: $importerPresented) {
        FilePicker(
          onPick: { urls in
            model.selection.append(contentsOf: urls.compactMap(SelectedFile.make(from:)))
            importerPresented = false
          },
          onCancel: { importerPresented = false }
        )
      }
      .sheet(isPresented: $folderPickerPresented) {
        FilePicker(contentTypes: [.folder], allowsMultipleSelection: false,
          onPick: { urls in
            model.selection.append(contentsOf: urls.flatMap(SelectionStaging.files(in:)))
            folderPickerPresented = false
          },
          onCancel: { folderPickerPresented = false }
        )
      }
      .sheet(isPresented: $mediaPickerPresented) {
        MediaPicker(onPick: { urls in
          model.selection.append(contentsOf: urls.compactMap(SelectedFile.make(from:)))
          mediaPickerPresented = false
        }, onCancel: { mediaPickerPresented = false })
      }
      .sheet(isPresented: $textSheetPresented) {
        NavigationStack {
          TextEditor(text: $textDraft)
            .padding(12)
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { textSheetPresented = false }
              }
              ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                  do { model.selection.append(try SelectionStaging.text(textDraft)) }
                  catch { model.errorMessage = error.localizedDescription }
                  textSheetPresented = false
                }
                .disabled(textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              }
            }
        }
      }
      .sheet(isPresented: $favoriteSheetPresented) {
        AddFavoriteSheet { alias, host in
          model.addFavorite(alias: alias, host: host)
        }
      }
      .sheet(item: $detailsDevice) { device in
        DeviceDetailsSheet(device: device)
      }
      .sheet(isPresented: $scannerPresented) {
        QRScannerView(
          onCode: { code in
            handleScanned(code: code, model: model)
          },
          onCancel: { scannerPresented = false }
        )
        .ignoresSafeArea()
      }
    }
  }

  @ViewBuilder
  private func selectionCard(model: AppModel) -> some View {
    if model.selection.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Selection")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
          selectionButton("Media", symbol: "photo") { mediaPickerPresented = true }
          selectionButton("Text", symbol: "text.alignleft") { textSheetPresented = true }
          selectionButton("Clipboard", symbol: "doc.on.clipboard") {
            do {
              let files = try SelectionStaging.clipboard()
              if files.isEmpty { model.errorMessage = String(localized: "Clipboard is empty") }
              model.selection.append(contentsOf: files)
            } catch { model.errorMessage = error.localizedDescription }
          }
          selectionButton("File", symbol: "doc") { importerPresented = true }
          selectionButton("Folder", symbol: "folder") { folderPickerPresented = true }
        }
      }
    } else {
      GlassCard(cornerRadius: AppRadius.control) {
        VStack(alignment: .leading, spacing: 12) {
        HStack {
          SectionHeader(title: "Selection")
          Spacer(minLength: 0)
          Button("Clear") { model.selection = [] }
            .font(.footnote)
        }

          ForEach(model.selection) { file in
            HStack(spacing: 12) {
              Image(systemName: "doc.fill")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .glassPanel(cornerRadius: AppRadius.control)
              VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(1)
                Text(Int64(file.size).formattedSize)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Button {
                model.selection.removeAll { $0.id == file.id }
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }

          Text("\(model.selection.count) · \(model.selectionBytes.formattedSize)")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button {
          importerPresented = true
        } label: {
          Label("Add files", systemImage: "plus")
        }
        .buttonStyle(GlassProminentButtonStyle())
        }
      }
    }
  }

  private func selectionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: symbol).font(.title3)
        Text(LocalizedStringKey(title)).font(.subheadline).lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 68)
      .glassPanel(interactive: true)
    }
    .buttonStyle(.plain)
  }

  private var favoritesCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Favourites")
        ForEach(model.favorites.devices) { favorite in
          HStack(spacing: 12) {
            Image(systemName: "star.fill")
              .font(.system(size: 18))
              .foregroundStyle(.yellow)
              .frame(width: 46, height: 46)
              .glassPanel(cornerRadius: AppRadius.control)

            VStack(alignment: .leading, spacing: 2) {
              Text(favorite.alias)
                .font(.subheadline.weight(.medium))
              Text("\(favorite.host):\(String(favorite.port))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
              send(to: favorite.asDevice)
            } label: {
              Image(systemName: "paperplane.fill")
                .foregroundStyle(model.selection.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.plain)
            .disabled(model.selection.isEmpty)
          }
          .contextMenu {
            Button {
              detailsDevice = favorite.asDevice
            } label: {
              Label("Details", systemImage: "info.circle")
            }
            Button("Remove", role: .destructive) {
              model.favorites.remove(fingerprint: favorite.fingerprint)
            }
          }
        }
      }
    }
  }

  private var devicesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
          SectionHeader(title: "Nearby")
          Spacer(minLength: 0)
          if model.discovery.isScanning {
            ProgressView().controlSize(.small)
          }
          Button {
            Task { await model.discovery.scan() }
          } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
          }
          .accessibilityLabel("Scan now")
          Button { scannerPresented = true } label: {
            Image(systemName: "qrcode.viewfinder")
          }
          .accessibilityLabel("Scan QR code")
          Button { favoriteSheetPresented = true } label: {
            Image(systemName: "heart.fill")
          }
          .accessibilityLabel("Add favourite")
          NavigationLink { SettingsView(settings: model.settings) } label: {
            Image(systemName: "gearshape.fill")
          }
          .accessibilityLabel("Settings")
        }

        if model.discovery.devices.isEmpty {
          HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
              .font(.title2)
            Text(LocalizedStringKey(model.discovery.isScanning ? "Scanning the local network…" : "No device found yet. Pull to rescan."))
              .font(.subheadline)
          }
          .foregroundStyle(.secondary)
          .opacity(0.45)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .glassPanel(cornerRadius: AppRadius.control)
        } else {
          ForEach(model.discovery.devices) { device in
            Button {
              send(to: device)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: device.deviceType.symbolName)
                  .font(.system(size: 20))
                  .foregroundStyle(.tint)
                  .frame(width: 46, height: 46)
                  .glassPanel(cornerRadius: AppRadius.control)

                VStack(alignment: .leading, spacing: 2) {
                  Text(device.alias)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                  Text("\(device.host):\(String(device.port)) · \(device.protocolName.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "paperplane.fill")
                  .foregroundStyle(model.selection.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.selection.isEmpty)
            .padding(10)
            .glassPanel(cornerRadius: AppRadius.control, interactive: true)
            .contextMenu {
              Button {
                detailsDevice = device
              } label: {
                Label("Details", systemImage: "info.circle")
              }
              Button {
                model.favorites.toggle(
                  FavoriteDevice(
                    fingerprint: device.fingerprint,
                    alias: device.alias,
                    host: device.host,
                    port: device.port,
                    deviceType: device.deviceType.rawValue,
                    protocolName: device.protocolName
                  )
                )
              } label: {
                Label("Add favourite", systemImage: "star")
              }
            }
          }
        }
    }
  }

  private func send(to device: Device) {
    let files = model.selection
    guard !files.isEmpty else { return }
    model.selection = []
    model.send(files: files, to: device)
  }

  /// A scanned LocalSend code is either a pairing URL or a bare host.
  private func handleScanned(code: String, model: AppModel) {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
      model.addFavorite(alias: host, host: host)
    } else if !trimmed.isEmpty {
      model.addFavorite(alias: trimmed, host: trimmed)
    }
    scannerPresented = false
  }
}

/// Add a favourite by address, like the Flutter `favorite_dialog`.
struct AddFavoriteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var alias = ""
  @State private var host = ""

  let onSave: (String, String) -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        GlassCard {
          VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $alias)
              .textFieldStyle(.roundedBorder)
            TextField("192.168.178.20", text: $host)
              .textFieldStyle(.roundedBorder)
              .keyboardType(.decimalPad)
              .autocorrectionDisabled()
          }
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      .background(AmbientBackground())
      .navigationTitle("Add favourite")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(alias, host)
            dismiss()
          }
          .disabled(alias.trimmingCharacters(in: .whitespaces).isEmpty || host.isEmpty)
        }
      }
    }
    .presentationDetents([.height(300)])
  }
}

extension FavoriteDevice {
  var asDevice: Device {
    Device(
      id: fingerprint,
      alias: alias,
      deviceType: DeviceType(wire: deviceType),
      host: host,
      port: port,
      lastSeen: Date(),
      protocolName: protocolName
    )
  }
}
