import SwiftUI

struct ReceiveView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          hero
          serverCard
          if model.settings.downloadEnabled { downloadCard }
          receivedCard
        }
        .padding(20)
      }
      .background(AmbientBackground())
      .navigationTitle("Receive")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            HistoryView()
          } label: {
            Image(systemName: "clock.arrow.circlepath")
          }
        }
      }
      .refreshable { model.refreshIdentity() }
    }
  }

  private var hero: some View {
    GlassCard {
      VStack(spacing: 12) {
        Image(systemName: "wifi")
          .font(.system(size: 40, weight: .regular))
          .foregroundStyle(.tint)
          .frame(width: 104, height: 104)
          .glassPanel(cornerRadius: 52, interactive: true)

        Text(model.deviceIdentity.alias)
          .font(.system(size: 30, weight: .semibold, design: .rounded))
          .multilineTextAlignment(.center)

        Text("\(model.primaryAddress):\(String(model.deviceIdentity.port))")
          .font(.system(.subheadline, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
    }
  }

  private var serverCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Server")
        row("State", model.serverRunning ? "Running" : "Stopped")
        row("Protocol", model.settings.encryption ? "HTTPS · v2.2" : "HTTP · v2.2")
        row("Port", String(model.deviceIdentity.port))
        row("PIN", model.settings.pin.isEmpty ? "Off" : "On")
        row("Fingerprint", String(model.identity.fingerprint.prefix(16)))
        Button {
          model.refreshIdentity()
        } label: {
          Label("Refresh network info", systemImage: "arrow.clockwise")
        }
        .buttonStyle(GlassProminentButtonStyle())
      }
    }
  }

  private var downloadCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeader(title: "Web download")
        Text(downloadURL)
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        Text("Open this address in a browser on the same network to download the received files.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var downloadURL: String {
    let scheme = model.settings.encryption ? "https" : "http"
    return "\(scheme)://\(model.primaryAddress):\(model.deviceIdentity.port)/"
  }

  private var receivedCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Received")
        if model.receivedFiles.isEmpty {
          Text("Files you receive land in Documents/LocalSend.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.receivedFiles) { file in
            HStack(spacing: 12) {
              Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
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
              ShareLink(item: file.url) {
                Image(systemName: "square.and.arrow.up")
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(value)
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
