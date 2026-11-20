import SwiftUI
import SwiftData
import GardenCore

/// The garden at a glance: one row per bed. Everything about a bed (its plants, photos and
/// history) lives on the bed's own screen.
struct GardenView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Bed.created) private var beds: [Bed]
    @Query(sort: \Plant.created) private var plants: [Plant]
    @Query(sort: \InventoryItem.created) private var inventory: [InventoryItem]

    @State private var addingBed = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                let loose = plants.filter { plant in plant.bedID == nil || !beds.contains { $0.id == plant.bedID } }
                Section {
                    ForEach(beds) { bed in
                        NavigationLink {
                            GardenRecordView(subject: .bed(bed.id))
                        } label: {
                            BedRow(bed: bed, plants: plants.filter { $0.bedID == bed.id })
                        }
                    }
                    if !loose.isEmpty {
                        NavigationLink {
                            UnassignedPlantsView()
                        } label: {
                            LooseRow(count: loose.reduce(0) { $0 + $1.count })
                        }
                    }
                    Button {
                        addingBed = true
                    } label: {
                        Label("Add a bed or container", systemImage: "plus")
                    }
                } header: {
                    Text("Beds")
                } footer: {
                    if beds.isEmpty {
                        Text("Add each bed, row or container, then open it to add what's growing there.")
                    }
                }

                Section {
                    NavigationLink {
                        InventoryView()
                    } label: {
                        HStack {
                            Label("What I have", systemImage: "shippingbox")
                            Spacer()
                            Text("\(inventory.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        CoachNotesView()
                    } label: {
                        Label("Things \(app.coachName) remembers", systemImage: "brain")
                    }
                } footer: {
                    Text("Suggestions start with what you have, then free options, then low-cost ones, then products to buy.")
                }
            }
            .navigationTitle("Garden")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $addingBed) {
                BedEditor(bed: nil)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

/// One bed in the Garden list: its name, kind and how many plants are in it.
struct BedRow: View {
    let bed: Bed
    let plants: [Plant]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bed.kind == .container ? "cube.box.fill" : "square.grid.2x2.fill")
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(bed.name)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let count = plants.reduce(0) { $0 + $1.count }
        let what = count == 0 ? "No plants yet" : (count == 1 ? "1 plant" : "\(count) plants")
        return "\(bed.kind.displayName) · \(what)"
    }
}

private struct LooseRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not in a bed")
                    .font(.headline)
                Text(count == 1 ? "1 plant" : "\(count) plants")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Plants that aren't in any bed (added without one, or left over from a deleted bed).
struct UnassignedPlantsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Bed.created) private var beds: [Bed]
    @Query(sort: \Plant.created) private var plants: [Plant]
    @State private var adding = false

    init() {}

    private var loose: [Plant] {
        plants.filter { plant in plant.bedID == nil || !beds.contains { $0.id == plant.bedID } }
    }

    var body: some View {
        List {
            Section {
                ForEach(loose) { plant in
                    NavigationLink {
                        GardenRecordView(subject: .plant(plant.id))
                    } label: {
                        PlantRow(plant: plant)
                    }
                }
                .onDelete { offsets in deletePlants(offsets, from: loose, context: context, app: app) }
                Button {
                    adding = true
                } label: {
                    Label("Add a plant", systemImage: "plus")
                }
            } footer: {
                Text("To move a plant into a bed, open it and tap Edit.")
            }
        }
        .navigationTitle("Not in a bed")
        .sheet(isPresented: $adding) {
            PlantEditor(plant: nil, defaultBedID: nil)
        }
    }
}

/// Swipe-to-delete for a list of plants.
@MainActor
func deletePlants(_ offsets: IndexSet, from list: [Plant], context: ModelContext, app: AppModel) {
    for index in offsets where index < list.count {
        context.delete(list[index])
    }
    app.save()
    Task { await app.replanNudges() }
}

struct PlantRow: View {
    @Environment(AppModel.self) private var app
    let plant: Plant

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(plant.count > 1 ? "\(plant.name) × \(plant.count)" : plant.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if plant.crop.needsSupport {
                Image(systemName: plant.staked ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(plant.staked ? Color.green : Color.orange)
                    .accessibilityLabel(plant.staked ? "Staked" : "Not staked yet")
            }
        }
    }

    private var subtitle: String {
        var parts = [plant.crop.name, plant.stage.displayName.lowercased()]
        if let planted = plant.plantedDay {
            let days = planted.days(to: app.today, calendar: app.calendar)
            if days >= 0 { parts.append("\(days) days in") }
        }
        return parts.joined(separator: " · ")
    }
}

struct BedEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let bed: Bed?

    init(bed: Bed?) {
        self.bed = bed
    }

    @State private var name = ""
    @State private var kind: BedKind = .raised
    @State private var soil: SoilType = .unknown
    @State private var sun: SunExposure = .fullSun
    @State private var irrigation: IrrigationKind = .hose
    @State private var mulch = ""
    @State private var areaText = ""
    @State private var phText = ""
    @State private var soilTestNotes = ""
    @State private var notes = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(BedKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    HStack {
                        Text("Size")
                        Spacer()
                        TextField("sq ft", text: $areaText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("sq ft").foregroundStyle(.secondary)
                    }
                }
                Section("Growing conditions") {
                    Picker("Soil", selection: $soil) {
                        ForEach(SoilType.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Sun", selection: $sun) {
                        ForEach(SunExposure.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Watering", selection: $irrigation) {
                        ForEach(IrrigationKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("Mulch (straw, leaves, chips, or blank)", text: $mulch)
                }
                Section("Soil test") {
                    HStack {
                        Text("pH")
                        Spacer()
                        TextField("e.g. 6.5", text: $phText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    TextField("Results or notes", text: $soilTestNotes, axis: .vertical)
                }
                Section("Notes") {
                    TextField("Anything else", text: $notes, axis: .vertical)
                }
                if bed != nil {
                    Section {
                        Button("Delete bed", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Plants in this bed are kept and moved to \"Not in a bed\".")
                    }
                }
            }
            .navigationTitle(bed == nil ? "New bed" : "Edit bed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this bed?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete bed", role: .destructive, action: deleteBed)
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let bed = bed else { return }
        name = bed.name
        kind = bed.kind
        soil = bed.soil
        sun = bed.sun
        irrigation = bed.irrigation
        mulch = bed.mulch
        areaText = bed.areaSqFt.map { String(format: "%g", $0) } ?? ""
        phText = bed.soilPH.map { String(format: "%g", $0) } ?? ""
        soilTestNotes = bed.soilTestNotes
        notes = bed.notes
    }

    private func save() {
        let target: Bed
        if let bed = bed {
            target = bed
        } else {
            target = Bed(name: name)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind
        target.soil = soil
        target.sun = sun
        target.irrigation = irrigation
        target.mulch = mulch.trimmingCharacters(in: .whitespacesAndNewlines)
        target.areaSqFt = Double(areaText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        target.soilPH = Double(phText.trimmingCharacters(in: .whitespaces)).flatMap { (3...10).contains($0) ? $0 : nil }
        target.soilTestNotes = soilTestNotes
        target.notes = notes
        app.save()
        Task { await app.replanNudges() }
        dismiss()
    }

    private func deleteBed() {
        guard let bed = bed else { return }
        context.delete(bed)
        app.save()
        Task { await app.replanNudges() }
        dismiss()
    }
}

struct PlantEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bed.created) private var beds: [Bed]
    let plant: Plant?
    let defaultBedID: UUID?

    init(plant: Plant?, defaultBedID: UUID?) {
        self.plant = plant
        self.defaultBedID = defaultBedID
    }

    @State private var name = ""
    @State private var cropID = CropCatalog.other.id
    @State private var cropTouched = false
    @State private var bedID: UUID?
    @State private var hasPlantedDate = false
    @State private var plantedDate = Date()
    @State private var stage: GrowthStage = .vegetative
    @State private var count = 1
    @State private var staked = false
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like \"Sungold\" or \"Basil\"", text: $name)
                        .onChange(of: name) { _, newName in
                            if !cropTouched, let guess = CropCatalog.guess(from: newName) { cropID = guess.id }
                        }
                    Picker("Type", selection: Binding(get: { cropID }, set: { cropID = $0; cropTouched = true })) {
                        ForEach(CropCatalog.all) { crop in
                            Text(crop.name).tag(crop.id)
                        }
                        Text(CropCatalog.other.name).tag(CropCatalog.other.id)
                    }
                    Picker("Bed", selection: $bedID) {
                        Text("Not in a bed").tag(UUID?.none)
                        ForEach(beds) { bed in
                            Text(bed.name).tag(UUID?.some(bed.id))
                        }
                    }
                    Stepper("How many: \(count)", value: $count, in: 1...200)
                }
                Section("Growth") {
                    Picker("Stage", selection: $stage) {
                        ForEach(GrowthStage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("I know when it was planted", isOn: $hasPlantedDate)
                    if hasPlantedDate {
                        DatePicker("Planted", selection: $plantedDate, in: ...Date(), displayedComponents: .date)
                    }
                    if CropCatalog.profile(for: cropID).needsSupport {
                        Toggle("Staked, caged or trellised", isOn: $staked)
                    }
                }
                Section("Notes") {
                    TextField("Variety, where you got it, anything", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(plant == nil ? "New plant" : "Edit plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        bedID = defaultBedID
        guard let plant = plant else { return }
        name = plant.name
        cropID = plant.cropID ?? CropCatalog.other.id
        cropTouched = true
        bedID = plant.bedID
        if let day = plant.plantedDay {
            hasPlantedDate = true
            plantedDate = day.date(atMinute: 12 * 60, in: app.calendar)
        }
        stage = plant.stage
        count = plant.count
        staked = plant.staked
        notes = plant.notes
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let planted = hasPlantedDate ? LocalDay(plantedDate, calendar: app.calendar) : nil
        let target: Plant
        if let plant = plant {
            target = plant
        } else {
            target = Plant(name: trimmed, cropID: cropID, bedID: bedID, plantedOn: planted, stage: stage)
            context.insert(target)
        }
        target.name = trimmed
        target.cropID = cropID == CropCatalog.other.id ? nil : cropID
        target.bedID = bedID
        target.plantedDay = planted
        target.stage = stage
        target.count = count
        target.staked = staked
        target.notes = notes
        if plant == nil, let day = planted {
            let entry = JournalEntry(day: day, kind: .planting, what: "Planted \(trimmed)")
            entry.plantID = target.id
            entry.plantName = trimmed
            entry.bedID = bedID
            entry.bedName = beds.first { $0.id == bedID }?.name ?? ""
            context.insert(entry)
        }
        app.save()
        Task { await app.replanNudges() }
        dismiss()
    }
}
