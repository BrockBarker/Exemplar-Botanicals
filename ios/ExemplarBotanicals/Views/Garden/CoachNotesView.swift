import SwiftUI
import SwiftData
import GardenCore

/// What the coach remembers: lasting facts ("rain barrel by the shed") and what the gardener
/// has on hand, both picked up from chats. There's no form for supplies; the gardener just
/// tells the coach, and can swipe away anything wrong or used up here.
struct CoachNotesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \CoachNote.created, order: .reverse) private var notes: [CoachNote]
    @Query(sort: \InventoryItem.name) private var supplies: [InventoryItem]
    @State private var newFact = ""

    var body: some View {
        List {
            Section {
                TextField("Add something to remember", text: $newFact)
                    .onSubmit(add)
            } footer: {
                Text("\(app.coachName) saves things like this when you mention them in a chat, and uses them in every answer.").onPhoto()
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
            if !supplies.isEmpty {
                Section {
                    ForEach(supplies) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(item.quantity)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets where index < supplies.count { context.delete(supplies[index]) }
                        app.save()
                    }
                } header: {
                    Text("On hand").onPhoto()
                } footer: {
                    Text("From your chats. Swipe left on anything that's wrong or used up.").onPhoto()
                }
            }
        }
        .gardenBackground()
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
