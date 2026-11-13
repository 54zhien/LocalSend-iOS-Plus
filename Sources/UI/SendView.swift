import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
  @Environment(AppModel.self) private var model
  @State private var files: [SelectedFile] = []
  @State private var importing = false
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          filesCard
          devicesCard
        }
        .padding(16)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .navigationTitle("Send")
      .refreshable { await model.discovery.scan() }
      .fileImporter(
        isPresented: $importing,
        allowedContentTypes: [.item],
        allowsMultipleSelection: true
      ) { result in
        switch result {
        case let .success(urls):
          files = urls.compactMap(SelectedFile.make(from:))
        case let .failure(error):
          failure = error.localizedDescription
        }
      }
      .alert("Could not pick files", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
        Button("OK", role: .cancel) { failure = nil }
      } message: {
        Text(failure ?? "")
      }
    }
  }

  private var filesCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          SectionHeader(title: "Selection")
          Spacer()
          if !files.isEmpty {
            Button("Clear") { files = [] }
              .font(.footnote.weight(.semibold))
          }
        }
        if files.isEmpty {
          Text("Pick files, then tap a device.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          ForEach(files) { file in
            HStack(spacing: 12) {
              Image(systemName: "doc.fill")
                .frame(width: 30, height: 30)
                .glassPanel(cornerRadius: 8)
              VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(1)
                Text(Int64(file.size).formattedSize)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
          }
          Text("\(files.count) file(s) · \(Int64(files.reduce(0) { $0 + $1.size }).formattedSize)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Button {
          importing = true
        } label: {
          Label("Add files", systemImage: "plus")
        }
        .buttonStyle(GlassProminentButtonStyle())
      }
    }
  }

  private var devicesCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionHeader(title: "Nearby devices")
        Spacer()
        if model.discovery.isScanning {
          ProgressView().controlSize(.small)
        }
      }
      if model.discovery.devices.isEmpty {
        GlassCard {
          VStack(alignment: .leading, spacing: 6) {
            Text(model.discovery.isScanning ? "Scanning the local network…" : "No devices found yet")
              .font(.subheadline.weight(.medium))
            Text("Both devices need LocalSend open, on the same Wi-Fi.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      } else {
        ForEach(model.discovery.devices) { device in
          Button {
            guard !files.isEmpty else { return }
            model.send(files: files, to: device)
            files = []
          } label: {
            HStack(spacing: 14) {
              Image(systemName: device.deviceType.symbolName)
                .font(.title2)
                .frame(width: 46, height: 46)
                .glassPanel(cornerRadius: 14)
              VStack(alignment: .leading, spacing: 2) {
                Text(device.alias)
                  .font(.headline)
                  .lineLimit(1)
                Text("\(device.host):\(device.port)")
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "paperplane.fill")
                .foregroundStyle(files.isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.accentColor))
            }
            .padding(14)
            .glassPanel(cornerRadius: 22, interactive: true)
          }
          .buttonStyle(.plain)
          .disabled(files.isEmpty)
        }
      }
    }
  }
}
