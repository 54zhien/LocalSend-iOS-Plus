import SwiftUI

struct TransferProgressView: View {
  @Environment(AppModel.self) private var model

  /// Read from the model so progress updates publish while the sheet is open.
  private var transfer: OutgoingTransfer {
    model.outgoing
      ?? OutgoingTransfer(
        id: "none",
        deviceAlias: "",
        fileNames: [],
        completed: 0,
        total: 0,
        isFinished: true,
        error: nil
      )
  }

  var body: some View {
    VStack(spacing: 18) {
      Capsule()
        .fill(.secondary.opacity(0.4))
        .frame(width: 36, height: 5)
        .padding(.top, 8)

      Image(systemName: transfer.error == nil ? "paperplane.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 34, weight: .light))
        .frame(width: 78, height: 78)
        .glassPanel(cornerRadius: AppRadius.control)

      Text(transfer.deviceAlias)
        .font(.title3.weight(.semibold))

      if let error = transfer.error {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      } else {
        ProgressView(value: Double(transfer.completed), total: Double(max(transfer.total, 1)))
          .tint(.localSendAccent)
        Text(transfer.isFinished ? String(localized: "Sent files") : String(localized: "Sending files"))
          .font(.footnote)
          .foregroundStyle(.secondary)
        Text("\(transfer.completed) / \(transfer.total)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if transfer.isFinished || transfer.error != nil {
        Button("Done") { model.dismissOutgoing() }
          .buttonStyle(GlassProminentButtonStyle())
      }

      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AmbientBackground())
    .presentationDetents([.height(400)])
    .presentationDragIndicator(.hidden)
    .interactiveDismissDisabled(!transfer.isFinished && transfer.error == nil)
  }
}
