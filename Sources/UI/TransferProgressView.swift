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
    VStack(spacing: 12) {
      Image(systemName: transfer.error == nil ? "paperplane.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 28, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: 64, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))

      Text(transfer.deviceAlias)
        .font(.title3.weight(.semibold))
        .lineLimit(1)
      if let first = transfer.fileNames.first {
        Text(transfer.fileNames.count == 1 ? first : "\(first) +\(transfer.fileNames.count - 1)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if let error = transfer.error {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      } else {
        ProgressView(value: Double(transfer.completed), total: Double(max(transfer.total, 1)))
          .tint(model.settings.accentColor)
        HStack {
          Text(transfer.isFinished ? String(localized: "Sent files") : transfer.sessionId == nil ? String(localized: "Connecting and preparing…") : String(localized: "Sending files"))
          .font(.footnote)
          .foregroundStyle(.secondary)
          Spacer()
          Text("\(transfer.completed) / \(transfer.total)")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      if transfer.isFinished || transfer.error != nil {
        Button("Done") { model.dismissOutgoing() }
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 13)
          .background(.regularMaterial, in: Capsule())
          .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 28)
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity)
    .background(AmbientBackground())
    .presentationDetents([.height(315)])
    .presentationDragIndicator(.visible)
    .interactiveDismissDisabled(!transfer.isFinished && transfer.error == nil)
  }
}
