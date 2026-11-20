import SwiftUI
import SwiftData
import UIKit
import GardenCore

/// The garden journal: everything done and noticed, newest first. Nudges and the coach add to
/// it too, and the water and feeding estimates read from it.
struct JournalView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.created, order: .reverse) private var entries: [JournalEntry]

    @State private var editing: JournalEntry?
    @State private var adding = false
    @State private var filter: JournalKind?

    private struct DayGroup: Identifiable {
        let day: String
        let entries: [JournalEntry]
        var id: String { day }
    }

    private var days: [DayGroup] {
        let shown = filter.map { kind in entries.filter { $0.kind == kind } } ?? entries
        let grouped = Dictionary(grouping: shown) { $0.day }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "book.closed",
                        description: Text("Log watering, feeding, sprays and what you notice. Tapping Done on a nudge adds it here too.")
                    )
                }
                ForEach(days) { group in
                    Section(header: Text(header(for: group.day))) {
                        ForEach(group.entries) { entry in
                            JournalRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = entry }
                        }
                        .onDelete { offsets in
                            for index in offsets where index < group.entries.count {
                                context.delete(group.entries[index])
                            }
                            app.save()
                            Task { await app.replanNudges() }
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Everything") { filter = nil }
                        ForEach(JournalKind.allCases) { kind in
                            Button {
                                filter = kind
                            } label: {
                                Label(kind.displayName, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label(filter?.displayName ?? "Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add entry")
                }
            }
            .sheet(item: $editing) { entry in
                JournalEntryEditor(entry: entry)
            }
            .sheet(isPresented: $adding) {
                JournalEntryEditor(entry: nil)
            }
        }
    }

    private func header(for day: String) -> String {
        guard let local = LocalDay(day) else { return day }
        return dayText(local, calendar: app.calendar)
    }
}

struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.what)
                let place = [entry.plantName, entry.bedName].filter { !$0.isEmpty }.joined(separator: " · ")
                if !place.isEmpty || !entry.amount.isEmpty {
                    Text([place, entry.amount].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if entry.source != "you" {
                    Text(sourceText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let data = entry.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var sourceText: String {
        switch entry.source {
        case "coach": return "Logged by the coach"
        case "nudge": return "From a nudge"
        case "photo": return "Photo check"
        default: return ""
        }
    }
}

struct JournalEntryEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bed.created) private var beds: [Bed]
    @Query(sort: \Plant.created) private var plants: [Plant]
    let entry: JournalEntry?

    @State private var date = Date()
    @State private var kind: JournalKind = .watering
    @State private var what = ""
    @State private var amount = ""
    @State private var bedID: UUID?
    @State private var plantID: UUID?
    @State private var moisture: MoistureReading?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What kind", selection: $kind) {
                        ForEach(JournalKind.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                    }
                    TextField(placeholder, text: $what, axis: .vertical)
                    TextField(amountPlaceholder, text: $amount)
                    DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if kind == .moistureCheck || kind == .watering {
                    Section("Finger test, 2 inches down") {
                        Picker("Soil felt", selection: $moisture) {
                            Text("Didn't check").tag(MoistureReading?.none)
                            ForEach(MoistureReading.allCases) { Text($0.displayName).tag(MoistureReading?.some($0)) }
                        }
                    }
                }
                Section("Where") {
                    Picker("Bed", selection: $bedID) {
                        Text("Whole garden").tag(UUID?.none)
                        ForEach(beds) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Plant", selection: $plantID) {
                        Text("All plants there").tag(UUID?.none)
                        ForEach(plantChoices) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section("Notes") {
                    TextField("Anything else", text: $notes, axis: .vertical)
                }
                if let entry = entry {
                    if let diagnosis = entry.diagnosis {
                        Section("Photo check") {
                            if let data = entry.photo, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            DiagnosisResultView(diagnosis: diagnosis)
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "New entry" : "Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(what.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var plantChoices: [Plant] {
        guard let bed = bedID else { return plants }
        return plants.filter { $0.bedID == bed }
    }

    private var placeholder: String {
        switch kind {
        case .watering: return "e.g. Deep soak with the hose"
        case .feeding: return "e.g. Fish emulsion, 1 Tbsp per gallon"
        case .foliarSpray: return "e.g. Kelp spray on the tomatoes"
        case .moistureCheck: return "e.g. Finger test"
        case .harvest: return "e.g. 3 lb of tomatoes"
        default: return "What happened"
        }
    }

    private var amountPlaceholder: String {
        kind == .watering ? "How much (e.g. 2 gallons, an inch)" : "Amount (optional)"
    }

    private func load() {
        guard let entry = entry else { return }
        date = entry.localDay.date(atMinute: 12 * 60, in: app.calendar)
        kind = entry.kind
        what = entry.what
        amount = entry.amount
        bedID = entry.bedID
        plantID = entry.plantID
        moisture = entry.moisture
        notes = entry.notes
    }

    private func save() {
        let day = LocalDay(date, calendar: app.calendar)
        let target: JournalEntry
        if let entry = entry {
            target = entry
        } else {
            target = JournalEntry(day: day, kind: kind, what: what)
            context.insert(target)
        }
        target.localDay = day
        target.kind = kind
        target.what = what.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        // Quick-log buttons store an exact amount; if the text is edited, read it from the text instead.
        if entry != nil && target.amount != newAmount { target.waterInches = nil }
        target.amount = newAmount
        let plant = plants.first { $0.id == plantID }
        let bed = beds.first { $0.id == (bedID ?? plant?.bedID) }
        target.bedID = bed?.id
        target.bedName = bed?.name ?? ""
        target.plantID = plant?.id
        target.plantName = plant?.name ?? ""
        target.moisture = (kind == .moistureCheck || kind == .watering) ? moisture : nil
        target.notes = notes
        app.save()
        Task { await app.replanNudges() }
        dismiss()
    }
}
