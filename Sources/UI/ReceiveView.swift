import SwiftUI

struct ReceiveView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showWebReceive = false
  @State private var showAdvanced = false
  @State private var spinning = false
  @State private var appeared = false

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 0) {
            Spacer(minLength: 40)
            hero
            Spacer(minLength: 40)
            Button {
              showWebReceive = true
            } label: {
              Label("Receive via link", systemImage: "globe")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 24)

            if model.settings.downloadEnabled { downloadCard.padding(.bottom, 16) }
            if !model.receivedFiles.isEmpty { receivedCard }
          }
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
          .frame(minHeight: geometry.size.height)
          .padding(.horizontal, 20)
        }
        .softTopScrollEdge()
      }
      .background(AmbientBackground())
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            HistoryView()
          } label: {
            Image(systemName: "clock.arrow.circlepath")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
          } label: {
            Image(systemName: "info.circle")
          }
        }
      }
      .overlay(alignment: .topTrailing) {
        if showAdvanced {
          serverCard
            .frame(maxWidth: 310)
            .padding(.top, 8)
            .padding(.trailing, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .zIndex(1)
        }
      }
      .refreshable { model.refreshIdentity() }
      .sheet(isPresented: $showWebReceive) {
        WebReceiveView()
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .onAppear {
        appeared = true
        spinning = model.serverRunning && model.settings.animations && !reduceMotion
      }
      .onDisappear { spinning = false }
      .onChange(of: model.serverRunning) { _, running in
        spinning = running && model.settings.animations && !reduceMotion
      }
    }
  }

  private var hero: some View {
    VStack(spacing: 12) {
      ZStack {
        Image("LocalSendLogoRing")
          .resizable()
          .renderingMode(.template)
          .foregroundStyle(.tint)
          .rotationEffect(.degrees(spinning ? 360 : 0))
          .animation(.linear(duration: 15).repeatForever(autoreverses: false), value: spinning)
        Image("LocalSendLogoCenter")
          .resizable()
          .renderingMode(.template)
          .foregroundStyle(.tint)
      }
      .frame(width: 200, height: 200)
      .opacity(appeared ? 1 : 0)
      .animation(.easeOut(duration: 0.3).delay(0.2), value: appeared)

      Text(model.deviceIdentity.alias)
        .font(.system(size: 48, weight: .regular))
        .minimumScaleFactor(0.55)
        .lineLimit(1)
        .multilineTextAlignment(.center)

      Text(visualIDs)
        .font(.system(size: 24))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.5), value: appeared)
    }
    .frame(maxWidth: .infinity)
  }

  private var visualIDs: String {
    guard model.serverRunning else { return String(localized: "Offline") }
    return model.addresses.map { "#\($0.split(separator: ".").last ?? "")" }.joined(separator: " ")
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
          Text("Files you receive land in Documents/LocalSend Plus.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.receivedFiles) { file in
            HStack(spacing: 12) {
              Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
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
      Text(LocalizedStringKey(label))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(LocalizedStringKey(value))
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }


}
