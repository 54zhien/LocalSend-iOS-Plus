import SwiftUI

struct SendView: View {
  @Environment(AppModel.self) private var model

  @State private var importerPresented = false
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
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            scannerPresented = true
          } label: {
            Image(systemName: "qrcode.viewfinder")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            favoriteSheetPresented = true
          } label: {
            Image(systemName: "star")
          }
        }
      }
      .refreshable { await model.discovery.scan() }
      .sheet(isPresented: $importerPresented) {
        FilePicker(
          onPick: { urls in
            model.selection = urls.compactMap(SelectedFile.make(from:))
            importerPresented = false
          },
          onCancel: { importerPresented = false }
        )
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
      VStack(alignment: .leading, spacing: 10) {
        SectionHeader(title: "Selection")
        Button {
          importerPresented = true
        } label: {
          VStack(spacing: 5) {
            Image(systemName: "doc.badge.plus")
              .font(.title3)
            Text("Add files")
              .font(.caption)
          }
          .frame(width: 90, height: 65)
          .glassPanel(cornerRadius: 10, interactive: true)
        }
        .buttonStyle(.plain)
      }
    } else {
      GlassCard(cornerRadius: 16) {
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
                .glassPanel(cornerRadius: 10)
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

          Text("\(model.selection.count) file\(model.selection.count == 1 ? "" : "s") · \(model.selectionBytes.formattedSize)")
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
              .glassPanel(cornerRadius: 14)

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
        }

        if model.discovery.devices.isEmpty {
          HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
              .font(.title2)
            Text(model.discovery.isScanning ? "Scanning the local network…" : "No device found yet. Pull to rescan.")
              .font(.subheadline)
          }
          .foregroundStyle(.secondary)
          .opacity(0.45)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .glassPanel(cornerRadius: 12)
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
                  .glassPanel(cornerRadius: 14)

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
            .glassPanel(cornerRadius: 12, interactive: true)
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
