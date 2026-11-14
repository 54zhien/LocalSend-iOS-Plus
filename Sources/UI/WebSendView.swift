import SwiftUI
import UIKit

struct WebSendView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var showingDownloadRequest = false

  let files: [SelectedFile]

  private var url: URL {
    URL(string: "http://\(model.primaryAddress):\(model.deviceIdentity.port)/")!
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          QRCodeView(url: url)
          Text(url.absoluteString)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
          Text("Open this link in a browser on the same Wi-Fi network to download the selected files.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Text("\(files.count) · \(files.reduce(Int64(0)) { $0 + Int64($1.size) }.formattedSize)")
            .font(.footnote)
            .foregroundStyle(.secondary)
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
      .navigationTitle("Share via link")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .onAppear { model.beginWebSend(files: files) }
    .onDisappear { model.endWebSend() }
    .onChange(of: model.downloadRequest?.id) { _, requestId in
      showingDownloadRequest = requestId != nil
    }
    .alert("Download request", isPresented: $showingDownloadRequest) {
      Button("Decline", role: .cancel) {
        if let request = model.downloadRequest { model.decideDownload(request, accepted: false) }
      }
      Button("Allow") {
        if let request = model.downloadRequest { model.decideDownload(request, accepted: true) }
      }
    } message: {
      Text(verbatim: "\(model.downloadRequest?.peerIp ?? "") ")
        + Text("wants to download the selected files.")
    }
  }
}
