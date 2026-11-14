import SwiftUI

/// Floating panel for adding a favourite by name and address.
///
/// It is deliberately not a sheet: the card hovers over a dimmed backdrop above the tab bar
/// and is dismissed by tapping the backdrop, pressing Cancel, or saving.
struct AddFavoritePanel: View {
  var onCancel: () -> Void
  var onSave: (_ alias: String, _ host: String) -> Void

  @State private var alias = ""
  @State private var host = ""
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case alias
    case host
  }

  private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSave: Bool { !trimmedAlias.isEmpty && !trimmedHost.isEmpty }

  var body: some View {
    ZStack {
      Color.black.opacity(0.22)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { cancel() }
        .accessibilityHidden(true)

      card
        .frame(maxWidth: 360)
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
    }
    .onAppear { focusedField = .alias }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Add favourite")
        .font(.headline)

      fieldGroup

      HStack(spacing: 12) {
        Spacer(minLength: 0)

        Button {
          cancel()
        } label: {
          Text("Cancel")
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        Button {
          save()
        } label: {
          Text("Save")
        }
        .buttonStyle(GlassProminentButtonStyle())
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
      }
    }
    .padding(20)
    .glassPanel(cornerRadius: 28)
  }

  private var fieldGroup: some View {
    VStack(spacing: 0) {
      TextField("Name", text: $alias)
        .textFieldStyle(.plain)
        .focused($focusedField, equals: .alias)
        .submitLabel(.next)
        .onSubmit { focusedField = .host }
        .padding(.horizontal, 18)
        .frame(height: 52)

      Divider().padding(.horizontal, 18)

      TextField("192.168.178.20", text: $host)
        .textFieldStyle(.plain)
        .focused($focusedField, equals: .host)
        .keyboardType(.decimalPad)
        .autocorrectionDisabled()
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
    )
  }

  private func cancel() {
    focusedField = nil
    onCancel()
  }

  private func save() {
    guard canSave else { return }
    focusedField = nil
    onSave(trimmedAlias, trimmedHost)
  }
}
