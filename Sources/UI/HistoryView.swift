import SwiftUI

/// Transfer history — the counterpart of the Flutter `receive_history_page`.
struct HistoryView: View {
  @Environment(AppModel.self) private var model

  private var grouped: [(day: Date, entries: [HistoryEntry])] {
    let calendar = Calendar.current
    let buckets = Dictionary(grouping: model.history.entries) { entry in
      calendar.startOfDay(for: entry.date)
    }
    return buckets
      .map { (day: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
      .sorted { $0.day > $1.day }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        if model.history.entries.isEmpty {
          GlassCard {
            VStack(spacing: 8) {
              Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
              Text("No transfers yet")
                .font(.headline)
              Text("Received and sent files show up here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
          }
        } else {
          ForEach(grouped, id: \.day) { group in
            VStack(alignment: .leading, spacing: 10) {
              SectionHeader(title: group.day.formatted(date: .abbreviated, time: .omitted))
              ForEach(group.entries) { entry in
                entryRow(entry)
              }
            }
          }
        }
      }
      .padding(20)
    }
    .background(AmbientBackground())
    .navigationTitle("History")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !model.history.entries.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Clear", role: .destructive) { model.history.clear() }
        }
      }
    }
  }

  private func entryRow(_ entry: HistoryEntry) -> some View {
    GlassCard(cornerRadius: 22) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Image(systemName: entry.direction == .received ? "arrow.down.circle" : "arrow.up.circle")
            .font(.system(size: 20))
            .foregroundStyle(entry.direction == .received ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
          Text(entry.alias)
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 0)
          Text(entry.date.formatted(date: .omitted, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 4) {
          ForEach(entry.files) { file in
            HStack(spacing: 8) {
              Image(systemName: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(file.name)
                .font(.caption)
                .lineLimit(1)
              Spacer(minLength: 0)
              Text(file.size.formattedSize)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
        Text("\(entry.files.count) file\(entry.files.count == 1 ? "" : "s") · \(entry.totalBytes.formattedSize)")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .contextMenu {
      Button("Delete", role: .destructive) { model.history.remove(entry) }
    }
  }
}
