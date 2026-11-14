import SwiftUI
import UIKit

struct WebReceiveView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private var url: URL {
    URL(string: "http://\(model.primaryAddress):\(model.deviceIdentity.port)/")!
  }

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      VStack(spacing: 18) {
          QRCodeView(url: url, size: 170)
          Text(url.absoluteString)
            .font(.system(size: 18, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
          Text("Open this link in a browser on the same Wi-Fi network, choose files, then approve the request here.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Spacer(minLength: 0)
          Button {
            UIPasteboard.general.url = url
          } label: {
            HStack {
              Spacer(minLength: 0)
              Label("Copy link", systemImage: "doc.on.doc")
                .font(.headline)
              Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .glassPanel(cornerRadius: 32, interactive: true)
          }
          .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(24)
      .background(AmbientBackground())
      .navigationTitle("Receive via link")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $model.incoming) { request in
      IncomingApprovalSheet(
        request: request,
        onAccept: { selected in model.accept(request, acceptedIds: selected) },
        onDecline: { model.decline(request) }
      )
    }
    .onAppear { model.beginWebReceive() }
    .onDisappear { model.endWebReceive() }
  }
}
