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
      ScrollView {
        VStack(spacing: 20) {
          QRCodeView(url: url)
          Text(url.absoluteString)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
          Text("Open this link in a browser on the same Wi-Fi network, choose files, then approve the request here.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button {
            UIPasteboard.general.url = url
          } label: {
            Label("Copy link", systemImage: "doc.on.doc")
          }
          .buttonStyle(GlassProminentButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
      }
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
