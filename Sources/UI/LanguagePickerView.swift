import SwiftUI

struct LanguagePickerView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var settings: AppSettings
  @State private var query = ""

  private var languages: [String] {
    Bundle.main.localizations
      .filter { $0 != "Base" }
      .sorted { name(for: $0).localizedStandardCompare(name(for: $1)) == .orderedAscending }
  }

  private var filteredLanguages: [String] {
    guard !query.isEmpty else { return languages }
    return languages.filter {
      $0.localizedCaseInsensitiveContains(query) || name(for: $0).localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        languageRow("system", title: "Follow system")
        ForEach(filteredLanguages, id: \.self) { code in
          languageRow(code, title: name(for: code))
        }
      }
      .searchable(text: $query)
      .navigationTitle("Language")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func languageRow(_ code: String, title: String) -> some View {
    Button {
      settings.languageCode = code
      dismiss()
    } label: {
      HStack {
        if code == "system" {
          Text("Follow system").foregroundStyle(.primary)
        } else {
          Text(title).foregroundStyle(.primary)
        }
        Spacer()
        if settings.languageCode == code {
          Image(systemName: "checkmark").foregroundStyle(.tint)
        }
      }
    }
  }

  private func name(for code: String) -> String {
    Locale(identifier: code).localizedString(forIdentifier: code) ?? code
  }
}
