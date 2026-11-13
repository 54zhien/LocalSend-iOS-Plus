import SwiftUI

struct ReceiveView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          heroCard
          if let incoming = model.incoming {
            incomingCard(incoming)
          }
          statusCard
          if !model.receivedFiles.isEmpty {
            recentCard
          }
        }
        .padding(16)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .navigationTitle("Receive")
    }
  }

  private var heroCard: some View {
    VStack(spacing: 14) {
      Image(systemName: "wifi")
        .font(.system(size: 54, weight: .light))
        .frame(width: 104, height: 104)
        .glassPanel(cornerRadius: 52)
      Text(model.identity.alias)
        .font(.system(size: 32, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
      Text(model.addresses.first.map { "\($0):\(model.identity.port)" } ?? "No network")
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 22)
    .glassPanel()
  }

  private func incomingCard(_ transfer: IncomingTransfer) -> some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 10) {
        Label(transfer.isFinished ? "Received" : "Receiving from \(transfer.peerAlias)", systemImage: "arrow.down.circle")
          .font(.headline)
        ProgressView(value: Double(transfer.received), total: Double(max(transfer.total, 1)))
          .tint(.accentColor)
        Text("\(transfer.received) of \(transfer.total) files")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var statusCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Server")
        row("State", model.serverRunning ? "Running" : "Stopped")
        row("Port", "\(model.identity.port)")
        row("Protocol", "HTTP · v2.2")
        row("Fingerprint", String(model.identity.fingerprint.prefix(12)) + "…")
        Divider().opacity(0.4)
        Button {
          model.refreshIdentity()
        } label: {
          Label("Refresh network info", systemImage: "arrow.clockwise")
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(GlassProminentButtonStyle())
      }
    }
  }

  private var recentCard: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Received")
        ForEach(model.receivedFiles) { file in
          HStack(spacing: 12) {
            Image(systemName: "doc.fill")
              .font(.title3)
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
            Spacer(minLength: 8)
            ShareLink(item: file.url) {
              Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
          }
        }
      }
    }
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
