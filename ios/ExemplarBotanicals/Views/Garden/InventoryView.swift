import SwiftUI
import SwiftData
import GardenCore

/// What the gardener already has: fertilizers, amendments, mulch, sprays, tools.
struct InventoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]

    @State private var newName = ""
    @State private var newCategory: InventoryCategory = .fertilizer
    @State private var newQuantity = ""

    var body: some View {
        List {
            Section {
                TextField("Add something, like \"Fish emulsion\"", text: $newName)
                Picker("Kind", selection: $newCategory) {
                    ForEach(InventoryCategory.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("How much (optional)", text: $newQuantity)
                Button("Add", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Include free things too: a compost pile, a leaf pile, coffee grounds from a café, a rain barrel.")
            }

            ForEach(InventoryCategory.allCases) { category in
                let group = items.filter { $0.category == category }
                if !group.isEmpty {
                    Section(category.displayName) {
                        ForEach(group) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.quantity)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets where index < group.count { context.delete(group[index]) }
                            app.save()
                        }
                    }
                }
            }
        }
        .navigationTitle("What I have")
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let item = InventoryItem(name: name, category: newCategory, quantity: newQuantity.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(item)
        app.save()
        newName = ""
        newQuantity = ""
    }
}

/// Lasting facts the coach saved ("rain barrel by the shed"). The gardener can remove any.
struct CoachNotesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \CoachNote.created, order: .reverse) private var notes: [CoachNote]
    @State private var newFact = ""

    var body: some View {
        List {
            Section {
                TextField("Add something to remember", text: $newFact)
                    .onSubmit(add)
            } footer: {
                Text("\(app.coachName) saves things like this when you mention them in a chat, and uses them in every answer.")
            }
            Section {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.fact)
                        Text(note.added)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets where index < notes.count { context.delete(notes[index]) }
                    app.save()
                }
            }
        }
        .navigationTitle("Remembered")
    }

    private func add() {
        let fact = newFact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fact.isEmpty else { return }
        context.insert(CoachNote(fact: fact, category: .other, added: app.today))
        app.save()
        newFact = ""
    }
}
