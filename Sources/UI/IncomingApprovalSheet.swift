import SwiftUI

/// Accept/decline sheet for an incoming upload — the SwiftUI counterpart of the Flutter
/// `receive_page`, with the same three choices (accept all, decline, per-file selection).
struct IncomingApprovalSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selected: Set<String>

  let request: IncomingRequest
  let onAccept: (Set<String>) -> Void
  let onDecline: () -> Void

  init(request: IncomingRequest, onAccept: @escaping (Set<String>) -> Void, onDecline: @escaping () -> Void) {
    self.request = request
    self.onAccept = onAccept
    self.onDecline = onDecline
    _selected = State(initialValue: Set(request.files.map(\.id)))
  }

  private var totalSize: Int64 {
    request.files.filter { selected.contains($0.id) }.reduce(0) { $0 + Int64($1.size) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          header
          fileList
        }
        .padding(20)
      }
      .background(AmbientBackground())
      .navigationTitle("Incoming")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Decline", role: .destructive) {
            onDecline()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(selected.isEmpty ? String(localized: "Accept") : "\(String(localized: "Accept")) \(selected.count)") {
            onAccept(selected)
            dismiss()
          }
          .disabled(selected.isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var header: some View {
    GlassCard {
      VStack(spacing: 10) {
        Image(systemName: "arrow.down.circle")
          .font(.system(size: 40, weight: .regular))
          .foregroundStyle(.tint)
        Text(request.peerAlias)
          .font(.title3.weight(.semibold))
        Text("\(String(localized: "Wants to send")) · \(request.files.count) · \(totalSize.formattedSize)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var fileList: some View {
    GlassCard {
      VStack(spacing: 12) {
        ForEach(request.files) { file in
          Button {
            if selected.contains(file.id) {
              selected.remove(file.id)
            } else {
              selected.insert(file.id)
            }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected.contains(file.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
              VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(1)
                Text(Int64(file.size).formattedSize)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

/// PIN entry for a receiver that requires one.
struct PinPromptSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var pin = ""
  @FocusState private var focused: Bool

  let alias: String
  let onSubmit: (String) -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        GlassCard {
          VStack(spacing: 12) {
            Image(systemName: "lock.fill")
              .font(.system(size: 32))
              .foregroundStyle(.tint)
            Text(alias)
              .font(.headline)
            Text("This device requires a PIN.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            TextField("PIN", text: $pin)
              .textFieldStyle(.roundedBorder)
              .keyboardType(.numberPad)
              .focused($focused)
              .multilineTextAlignment(.center)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      .background(AmbientBackground())
      .navigationTitle("PIN")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send") {
            onSubmit(pin)
            dismiss()
          }
          .disabled(pin.isEmpty)
        }
      }
    }
    .presentationDetents([.height(320)])
    .onAppear { focused = true }
  }
}
