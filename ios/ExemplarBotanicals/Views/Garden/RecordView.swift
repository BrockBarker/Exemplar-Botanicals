import SwiftUI
import SwiftData
import UIKit
import GardenCore

/// Which bed or plant a record is for.
enum RecordSubject: Hashable {
    case bed(UUID)
    case plant(UUID)
}

/// The running record for one bed or plant: its photos over time, before-and-after pairs around
/// each treatment, and everything logged for it. Built from the journal, so anything logged
/// anywhere (by hand, from a nudge, or by the coach) shows up here.
struct GardenRecordView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Bed.created) private var beds: [Bed]
    @Query(sort: \Plant.created) private var plants: [Plant]
    @Query(sort: \JournalEntry.created, order: .reverse) private var entries: [JournalEntry]
    let subject: RecordSubject

    @State private var editingBed: Bed?
    @State private var editingPlant: Plant?
    @State private var editingEntry: JournalEntry?
    @State private var addingPhoto = false
    @State private var logging = false
    @State private var viewing: PhotoViewerStart?
    @State private var comparing: TreatmentComparison?
    @State private var historyLimit = 15

    init(subject: RecordSubject) {
        self.subject = subject
    }

    /// Everything the screen shows, worked out once per redraw.
    private struct RecordData {
        var history: [JournalEntry]
        var photos: [JournalEntry]
        var groups: [TreatmentGroup]
        var treatmentCount: Int
        var byID: [UUID: JournalEntry]
    }

    private var bed: Bed? {
        guard case .bed(let id) = subject else { return nil }
        return beds.first { $0.id == id }
    }

    private var plant: Plant? {
        guard case .plant(let id) = subject else { return nil }
        return plants.first { $0.id == id }
    }

    private var scope: RecordScope? {
        if let bed = bed {
            return .bed(bed.id, plantIDs: Set(plants.filter { $0.bedID == bed.id }.map(\.id)))
        }
        if let plant = plant {
            return .plant(plant.id, bedID: plant.bedID)
        }
        return nil
    }

    private var title: String {
        bed?.name ?? plant?.name ?? "Record"
    }

    var body: some View {
        Group {
            if let scope = scope {
                content(makeData(scope))
            } else {
                ContentUnavailableView("Not in the garden anymore", systemImage: "leaf", description: Text("This was deleted."))
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    if let bed = bed {
                        editingBed = bed
                    } else if let plant = plant {
                        editingPlant = plant
                    }
                }
                .disabled(scope == nil)
            }
        }
        .sheet(item: $editingBed) { bed in
            BedEditor(bed: bed)
        }
        .sheet(item: $editingPlant) { plant in
            PlantEditor(plant: plant, defaultBedID: plant.bedID)
        }
        .sheet(item: $editingEntry) { entry in
            JournalEntryEditor(entry: entry)
        }
        .sheet(isPresented: $addingPhoto) {
            AddProgressPhotoSheet(subject: subject)
        }
        .sheet(isPresented: $logging) {
            JournalEntryEditor(entry: nil, defaultBedID: bed?.id ?? plant?.bedID, defaultPlantID: plant?.id)
        }
        .fullScreenCover(item: $viewing) { start in
            PhotoViewer(start: start)
        }
        .sheet(item: $comparing) { comparison in
            ComparisonView(
                comparison: comparison,
                treatmentEntry: entries.first { $0.id == comparison.treatment.id },
                before: entries.first { $0.id == comparison.before.id },
                after: entries.first { $0.id == comparison.after.id }
            )
        }
    }

    private func makeData(_ scope: RecordScope) -> RecordData {
        let newestFirst: (JournalEntry, JournalEntry) -> Bool = { a, b in
            a.day != b.day ? a.day > b.day : a.created > b.created
        }
        let history = entries
            .filter { ProgressRecord.belongs(kind: $0.kind, bedID: $0.bedID, plantID: $0.plantID, to: scope) }
            .sorted(by: newestFirst)
        let photos = entries
            .filter { entry in entry.progressPhoto.map { ProgressRecord.belongs($0, to: scope) } ?? false }
            .sorted(by: newestFirst)
        let treatments = history.filter { $0.kind.isTreatment }.map(\.info)
        let comparisons = ProgressRecord.comparisons(
            treatments: treatments,
            photos: photos.compactMap(\.progressPhoto),
            calendar: app.calendar
        )
        var byID: [UUID: JournalEntry] = [:]
        for entry in photos { byID[entry.id] = entry }
        return RecordData(
            history: history,
            photos: photos,
            groups: ProgressRecord.groups(comparisons),
            treatmentCount: treatments.count,
            byID: byID
        )
    }

    // MARK: Layout

    private func content(_ data: RecordData) -> some View {
        List {
            Section {
                summary
                HStack(spacing: 12) {
                    Button {
                        addingPhoto = true
                    } label: {
                        Label("Add photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        logging = true
                    } label: {
                        Label("Log something", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let bed = bed {
                plantsSection(bed)
            }
            photosSection(data)
            treatmentsSection(data)
            historySection(data)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let plant = plant {
            LabeledContent("Type", value: "\(plant.crop.name) · \(plant.stage.displayName.lowercased())")
            if let planted = plant.plantedDay {
                let days = planted.days(to: app.today, calendar: app.calendar)
                LabeledContent("Planted", value: days >= 0 ? "\(dayText(planted, calendar: app.calendar)) · \(days) days ago" : dayText(planted, calendar: app.calendar))
            }
            if let bed = beds.first(where: { $0.id == plant.bedID }) {
                NavigationLink {
                    GardenRecordView(subject: .bed(bed.id))
                } label: {
                    LabeledContent("Bed", value: bed.name)
                }
            }
            if plant.crop.needsSupport {
                LabeledContent("Support", value: plant.staked ? "Staked or caged" : "Not staked yet")
            }
            if !plant.notes.isEmpty {
                Text(plant.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let bed = bed {
            LabeledContent("Kind", value: bed.kind.displayName)
            LabeledContent("Soil", value: bed.soil == .unknown ? "Not set" : bed.soil.displayName)
            LabeledContent("Sun", value: bed.sun.displayName.components(separatedBy: " (").first ?? bed.sun.displayName)
            if !bed.mulch.isEmpty {
                LabeledContent("Mulch", value: bed.mulch)
            }
            if let ph = bed.soilPH {
                LabeledContent("Soil pH", value: String(format: "%.1f", ph))
            }
        }
    }

    private func plantsSection(_ bed: Bed) -> some View {
        let here = plants.filter { $0.bedID == bed.id }
        return Section("Plants") {
            if here.isEmpty {
                Text("No plants in this bed yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(here) { plant in
                NavigationLink {
                    GardenRecordView(subject: .plant(plant.id))
                } label: {
                    PlantRow(plant: plant)
                }
            }
        }
    }

    private func photosSection(_ data: RecordData) -> some View {
        Section {
            if data.photos.isEmpty {
                Text("Take a photo every week or so, plus one when you feed, spray or amend. They line up here, and before-and-after pairs show up below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(data.photos.prefix(9)) { entry in
                        Button {
                            viewing = PhotoViewerStart(startID: entry.id, photos: data.photos)
                        } label: {
                            PhotoTile(entry: entry, label: shortDay(entry.localDay))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                if data.photos.count > 9 {
                    NavigationLink("See all \(data.photos.count) photos") {
                        PhotoGalleryView(title: title, photos: data.photos)
                    }
                }
            }
        } header: {
            Text(data.photos.isEmpty ? "Photos" : "Photos (\(data.photos.count))")
        }
    }

    private func treatmentsSection(_ data: RecordData) -> some View {
        Section {
            if data.groups.isEmpty {
                Text(data.treatmentCount == 0
                    ? "Feeding, sprays, soil amendments, mulch, pruning and pest treatments logged here will show before-and-after photos."
                    : "To see what a treatment did, take a photo of the plant on the day you apply it (or up to two weeks before), and another 3 to 30 days later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(data.groups) { group in
                Label {
                    HStack(spacing: 6) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                        if group.comparisons.count > 1 {
                            Text("· \(group.comparisons.count) times")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: group.kind.symbol)
                        .foregroundStyle(.tint)
                }
                ForEach(group.comparisons) { comparison in
                    Button {
                        comparing = comparison
                    } label: {
                        ComparisonRow(
                            comparison: comparison,
                            before: data.byID[comparison.before.id],
                            after: data.byID[comparison.after.id]
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Treatments and results")
        }
    }

    private func historySection(_ data: RecordData) -> some View {
        Section {
            if data.history.isEmpty {
                Text("Nothing logged yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(data.history.prefix(historyLimit)) { entry in
                JournalRow(entry: entry, showDay: true)
                    .contentShape(Rectangle())
                    .onTapGesture { editingEntry = entry }
            }
            if data.history.count > historyLimit {
                Button("Show more (\(data.history.count - historyLimit) older)") {
                    historyLimit += 30
                }
            }
        } header: {
            Text("History")
        }
    }

    private func shortDay(_ day: LocalDay) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = app.calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: day.date(atMinute: 12 * 60, in: app.calendar))
    }
}

/// A before photo, an after photo, and when each was taken relative to the treatment.
struct ComparisonRow: View {
    @Environment(AppModel.self) private var app
    let comparison: TreatmentComparison
    let before: JournalEntry?
    let after: JournalEntry?

    init(comparison: TreatmentComparison, before: JournalEntry?, after: JournalEntry?) {
        self.comparison = comparison
        self.before = before
        self.after = after
    }

    var body: some View {
        HStack(spacing: 10) {
            thumb(before)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            thumb(after)
            VStack(alignment: .leading, spacing: 3) {
                Text(dayText(comparison.treatment.day, calendar: app.calendar))
                    .font(.subheadline)
                Text("After: \(comparison.daysAfterTreatment(calendar: app.calendar)) days later")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !comparison.alsoApplied.isEmpty {
                    Text("Also: " + comparison.alsoApplied.map(\.what).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumb(_ entry: JournalEntry?) -> some View {
        Group {
            if let entry = entry {
                JournalPhotoView(entry: entry)
            } else {
                Rectangle().fill(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Before and after, full size, with what else was done in between.
struct ComparisonView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let comparison: TreatmentComparison
    let treatmentEntry: JournalEntry?
    let before: JournalEntry?
    let after: JournalEntry?

    init(comparison: TreatmentComparison, treatmentEntry: JournalEntry?, before: JournalEntry?, after: JournalEntry?) {
        self.comparison = comparison
        self.treatmentEntry = treatmentEntry
        self.before = before
        self.after = after
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    photo(
                        before,
                        title: "Before",
                        caption: relative(comparison.before.day.days(to: comparison.treatment.day, calendar: app.calendar), "before"),
                        day: comparison.before.day
                    )
                    photo(
                        after,
                        title: "After",
                        caption: relative(comparison.daysAfterTreatment(calendar: app.calendar), "after"),
                        day: comparison.after.day
                    )
                    if !comparison.alsoApplied.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Also done between these photos")
                                .font(.subheadline.weight(.semibold))
                            ForEach(comparison.alsoApplied) { other in
                                Label("\(other.what) · \(dayText(other.day, calendar: app.calendar))", systemImage: other.kind.symbol)
                                    .font(.subheadline)
                            }
                            Text("These may have played a part too.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Before and after")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        let treatment = comparison.treatment
        return VStack(alignment: .leading, spacing: 4) {
            Label(treatment.what, systemImage: treatment.kind.symbol)
                .font(.title3.weight(.semibold))
            Text([treatment.kind.displayName, dayText(treatment.day, calendar: app.calendar), treatment.amount, treatment.plantName]
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let notes = treatmentEntry?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
            }
        }
    }

    private func relative(_ days: Int, _ word: String) -> String {
        switch days {
        case 0: return "Same day"
        case 1: return "1 day \(word)"
        default: return "\(days) days \(word)"
        }
    }

    private func photo(_ entry: JournalEntry?, title: String, caption: String, day: LocalDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Text("\(dayText(day, calendar: app.calendar)) · \(caption)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let entry = entry {
                JournalPhotoView(entry: entry, size: .large, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if entry.what != AddProgressPhotoSheet.defaultTitle {
                    Text(entry.what)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Every photo for a bed or plant, newest first.
struct PhotoGalleryView: View {
    @Environment(AppModel.self) private var app
    let title: String
    let photos: [JournalEntry]
    @State private var viewing: PhotoViewerStart?

    init(title: String, photos: [JournalEntry]) {
        self.title = title
        self.photos = photos
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(photos) { entry in
                    Button {
                        viewing = PhotoViewerStart(startID: entry.id, photos: photos)
                    } label: {
                        PhotoTile(entry: entry, label: dayText(entry.localDay, calendar: app.calendar))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .navigationTitle("\(title): photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { start in
            PhotoViewer(start: start)
        }
    }
}

/// Which photo to open the viewer on, and the photos to swipe through.
struct PhotoViewerStart: Identifiable {
    let id = UUID()
    let startID: UUID
    let photos: [JournalEntry]
}

/// Full-screen photos in time order. Swipe to move through time; each photo lists what was done
/// to the plant or bed since the photo before it.
struct PhotoViewer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalEntry.created) private var allEntries: [JournalEntry]
    @Query(sort: \Plant.created) private var plants: [Plant]
    /// Oldest first, so swiping left moves forward in time.
    let photos: [JournalEntry]

    @State private var selection: UUID
    @State private var editing: JournalEntry?

    init(start: PhotoViewerStart) {
        photos = start.photos.sorted { a, b in a.day != b.day ? a.day < b.day : a.created < b.created }
        _selection = State(initialValue: start.startID)
    }

    var body: some View {
        let treatments = allEntries.filter { $0.kind.isTreatment }.map(\.info)
        let progress = photos.compactMap(\.progressPhoto)
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(photos) { entry in
                    page(entry, treatments: treatments, progress: progress)
                        .tag(entry.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(position)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        editing = photos.first { $0.id == selection }
                    }
                }
            }
            .sheet(item: $editing) { entry in
                JournalEntryEditor(entry: entry)
            }
        }
    }

    private var position: String {
        guard let index = photos.firstIndex(where: { $0.id == selection }) else { return "" }
        return "\(index + 1) of \(photos.count)"
    }

    private func page(_ entry: JournalEntry, treatments: [JournalInfo], progress: [ProgressPhoto]) -> some View {
        let context = entry.progressPhoto.map {
            ProgressRecord.context(for: $0, photos: progress, treatments: treatments, calendar: app.calendar)
        }
        return VStack(spacing: 0) {
            ZoomablePhoto(entry: entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            caption(entry, context: context)
        }
    }

    private func caption(_ entry: JournalEntry, context: PhotoContext?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline(entry))
                .font(.headline)
            if entry.what != AddProgressPhotoSheet.defaultTitle {
                Text(entry.what)
                    .font(.subheadline)
            }
            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if let context = context, !context.treatments.isEmpty {
                Text(context.previous.map { "Since the photo from \(dayText($0.day, calendar: app.calendar)):" } ?? "In the 30 days before:")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                ForEach(context.treatments) { treatment in
                    Label("\(treatment.what) · \(dayText(treatment.day, calendar: app.calendar))", systemImage: treatment.kind.symbol)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial)
    }

    private func headline(_ entry: JournalEntry) -> String {
        var parts = [dayText(entry.localDay, calendar: app.calendar)]
        let name = entry.plantName.isEmpty ? entry.bedName : entry.plantName
        if !name.isEmpty { parts.append(name) }
        if let planted = plants.first(where: { $0.id == entry.plantID })?.plantedDay {
            let days = planted.days(to: entry.localDay, calendar: app.calendar)
            if days >= 0 { parts.append("day \(days)") }
        }
        return parts.joined(separator: " · ")
    }
}

/// Adds a progress photo to a bed's or plant's record (as a journal observation with a photo).
struct AddProgressPhotoSheet: View {
    /// What a photo entry is called when no note is written.
    static let defaultTitle = "Progress photo"

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bed.created) private var beds: [Bed]
    @Query(sort: \Plant.created) private var plants: [Plant]
    let subject: RecordSubject

    @State private var image: UIImage?
    @State private var date = Date()
    @State private var plantID: UUID?
    @State private var note = ""
    @State private var saving = false

    init(subject: RecordSubject) {
        self.subject = subject
    }

    private var plantsInBed: [Plant] {
        guard case .bed(let id) = subject else { return [] }
        return plants.filter { $0.bedID == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    PhotoSourceButtons(chooseTitle: image == nil ? "Choose photo" : "Choose another") { picked, taken in
                        image = picked
                        if let taken = taken { date = min(taken, Date()) }
                    }
                } footer: {
                    Text("Shooting from the same spot and angle each time makes changes easier to see.")
                }
                if !plantsInBed.isEmpty {
                    Section {
                        Picker("Photo of", selection: $plantID) {
                            Text("The whole bed").tag(UUID?.none)
                            ForEach(plantsInBed) { plant in
                                Text(plant.name).tag(UUID?.some(plant.id))
                            }
                        }
                    }
                }
                Section {
                    DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("What do you see? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(Self.defaultTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(image == nil || saving)
                }
            }
        }
    }

    private func save() async {
        guard let image = image else { return }
        saving = true
        defer { saving = false }
        let data = await Task.detached(priority: .userInitiated) { ImagePrep.forJournal(image) }.value
        guard let data = data else { return }

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = JournalEntry(day: LocalDay(date, calendar: app.calendar), kind: .observation, what: trimmed.isEmpty ? Self.defaultTitle : trimmed)
        let plant: Plant?
        let bed: Bed?
        switch subject {
        case .plant(let id):
            plant = plants.first { $0.id == id }
            bed = beds.first { $0.id == plant?.bedID }
        case .bed(let id):
            plant = plantsInBed.first { $0.id == plantID }
            bed = beds.first { $0.id == id }
        }
        entry.plantID = plant?.id
        entry.plantName = plant?.name ?? ""
        entry.bedID = bed?.id
        entry.bedName = bed?.name ?? ""
        entry.setPhoto(data)
        context.insert(entry)
        app.save()
        dismiss()
    }
}
