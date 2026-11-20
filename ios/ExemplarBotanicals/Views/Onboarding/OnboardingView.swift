import SwiftUI
import SwiftData
import GardenCore

/// First run: meet the coach, then name, location, a first bed, what you have, and nudges.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    private enum Step: Int, CaseIterable {
        case welcome, location, bed, supplies, nudges
    }

    @State private var step: Step = .welcome

    // Welcome
    @State private var name = ""

    // Location
    @State private var placeQuery = ""
    @State private var place: GardenPlace?
    @State private var locating = false
    @State private var locationError: String?
    @State private var locationService = LocationService()

    // First bed
    @State private var bedName = ""
    @State private var bedKind: BedKind = .raised
    @State private var soil: SoilType = .unknown
    @State private var sun: SunExposure = .fullSun
    @State private var mulch = ""
    @State private var plantName = ""
    @State private var plants: [String] = []

    // Supplies
    @State private var supplies: Set<String> = []
    @State private var budgetText = ""
    @State private var avoidUrine = false

    @State private var finishing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .welcome: welcome
                    case .location: location
                    case .bed: firstBed
                    case .supplies: suppliesStep
                    case .nudges: nudges
                    }
                }
                .padding(20)
            }
            .dismissKeyboardOnScroll()
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { move(-1) }
                    }
                }
            }
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "Welcome"
        case .location: return "Your garden"
        case .bed: return "First bed"
        case .supplies: return "What you have"
        case .nudges: return "Nudges"
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                CoachAvatar(size: 120)
                Spacer()
            }
            Text("Hi, I'm \(app.coachName).")
                .font(.largeTitle.bold())
            Text("I'll help you grow a healthy organic garden: when to water, harvest, prune, stake, check for pests, sow again and feed, based on your own weather. Tell me what you have, and I'll always start with what's free or already in your shed.")
                .font(.body)
            Text("This is an AI coach built from \(app.coachName)'s advice and way of talking. \(app.coachName) isn't reading the chat.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("What should I call you?", text: $name)
                .textContentType(.givenName)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)
            if app.isDemo {
                Label("Demo mode: the live coach isn't connected yet. Everything else works.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where's your garden?")
                .font(.title2.bold())
            Text("Local weather drives the nudges: frost, heat, dry spells and good spraying windows. Only the town-level location is used.")
                .foregroundStyle(.secondary)
            Button {
                Task { await useCurrentLocation() }
            } label: {
                Label("Use my current location", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(locating)

            HStack {
                TextField("Or type a town or ZIP code", text: $placeQuery)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await findPlace() } }
                Button("Find") { Task { await findPlace() } }
                    .disabled(placeQuery.trimmingCharacters(in: .whitespaces).isEmpty || locating)
            }
            if locating {
                ProgressView()
            }
            if let place = place {
                Label(place.label, systemImage: "mappin.and.ellipse")
                    .font(.headline)
            }
            if let error = locationError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var firstBed: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tell me about one bed")
                .font(.title2.bold())
            Text("You can add more beds, pots and plants later in the Garden tab.")
                .foregroundStyle(.secondary)
            TextField("Name, like \"Back raised bed\"", text: $bedName)
                .textFieldStyle(.roundedBorder)
            Picker("Kind", selection: $bedKind) {
                ForEach(BedKind.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Soil", selection: $soil) {
                ForEach(SoilType.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Sun", selection: $sun) {
                ForEach(SunExposure.allCases) { Text($0.displayName).tag($0) }
            }
            TextField("Mulch, if any (straw, leaves, wood chips)", text: $mulch)
                .textFieldStyle(.roundedBorder)

            Text("What's growing in it?")
                .font(.headline)
            HStack {
                TextField("A plant, like \"Sungold tomato\"", text: $plantName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(addPlant)
                Button("Add", action: addPlant)
                    .disabled(plantName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(plants, id: \.self) { plant in
                HStack {
                    Image(systemName: "leaf")
                        .foregroundStyle(.tint)
                    Text(plant)
                    Spacer()
                    Text(CropCatalog.guess(from: plant)?.name ?? "Other")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct Supply: Identifiable {
        let name: String
        let category: InventoryCategory
        var id: String { name }
    }

    private static let commonSupplies: [Supply] = [
        Supply(name: "Compost", category: .compost),
        Supply(name: "Worm castings", category: .compost),
        Supply(name: "Shredded leaves", category: .mulch),
        Supply(name: "Straw", category: .mulch),
        Supply(name: "Wood chips", category: .mulch),
        Supply(name: "Fish emulsion", category: .fertilizer),
        Supply(name: "Liquid kelp / seaweed", category: .foliar),
        Supply(name: "Organic granular fertilizer", category: .fertilizer),
        Supply(name: "Bone meal", category: .fertilizer),
        Supply(name: "Garden lime", category: .amendment),
        Supply(name: "Old sheets for frost", category: .tool),
    ]

    private var suppliesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What do you already have?")
                .font(.title2.bold())
            Text("I'll suggest what you own first, then free options like compost, leaves or kitchen scraps, then cheap ones, and only then products to buy.")
                .foregroundStyle(.secondary)
            ForEach(Self.commonSupplies) { item in
                Toggle(item.name, isOn: Binding(
                    get: { supplies.contains(item.name) },
                    set: { on in
                        if on { supplies.insert(item.name) } else { supplies.remove(item.name) }
                    }
                ))
            }
            Divider()
            HStack {
                Text("Monthly garden budget")
                Spacer()
                TextField("$", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Leave diluted urine out of suggestions", isOn: $avoidUrine)
        }
    }

    private var nudges: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nudges, not nagging")
                .font(.title2.bold())
            Text("I'll send a heads-up when it matters: frost tonight, a heat wave coming, a bed that's probably dry, something ready to pick, a pest check, time to prune, stake or sow again.")
            VStack(alignment: .leading, spacing: 8) {
                Label("At most 2 a day", systemImage: "bell.badge")
                Label("Nothing between 9 PM and 7 AM", systemImage: "moon.zzz")
                Label("Routine ones arrive around 7:30 AM", systemImage: "sunrise")
                Label("Tap Done and it goes in your journal", systemImage: "checkmark.circle")
            }
            .foregroundStyle(.secondary)
            Text("You can change all of this in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                if step == .nudges {
                    Task { await finish(askForNotifications: true) }
                } else {
                    move(1)
                }
            } label: {
                Text(primaryLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(finishing)

            if step == .location || step == .bed || step == .supplies {
                Button("Skip for now") { move(1) }
                    .font(.subheadline)
            }
            if step == .nudges {
                Button("Not now") { Task { await finish(askForNotifications: false) } }
                    .font(.subheadline)
                    .disabled(finishing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Get started"
        case .nudges: return "Turn on nudges"
        default: return "Next"
        }
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        let next = Step(rawValue: step.rawValue + delta) ?? step
        withAnimation { step = next }
    }

    private func addPlant() {
        let trimmed = plantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        plants.append(trimmed)
        plantName = ""
    }

    private func useCurrentLocation() async {
        locating = true
        locationError = nil
        defer { locating = false }
        do {
            place = try await locationService.currentPlace()
        } catch {
            locationError = error.localizedDescription
        }
    }

    private func findPlace() async {
        locating = true
        locationError = nil
        defer { locating = false }
        do {
            place = try await locationService.place(named: placeQuery)
        } catch {
            locationError = error.localizedDescription
        }
    }

    private func finish(askForNotifications: Bool) async {
        finishing = true
        defer { finishing = false }
        let profile = GardenRepository.profile(context)
        profile.gardenerName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.avoidUrine = avoidUrine
        if let dollars = Double(budgetText.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) {
            profile.monthlyBudget = dollars
        }

        let trimmedBed = bedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBed.isEmpty || !plants.isEmpty {
            let bed = Bed(name: trimmedBed.isEmpty ? "My bed" : trimmedBed, kind: bedKind, soil: soil, sun: sun)
            bed.mulch = mulch.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(bed)
            for plant in plants {
                context.insert(Plant(name: plant, cropID: CropCatalog.guess(from: plant)?.id, bedID: bed.id, plantedOn: nil))
            }
        }
        for item in Self.commonSupplies where supplies.contains(item.name) {
            context.insert(InventoryItem(name: item.name, category: item.category))
        }

        if askForNotifications {
            profile.nudgesEnabled = await NotificationScheduler.requestPermission()
        } else {
            profile.nudgesEnabled = false
        }
        app.save()

        if let place = place {
            await app.setLocation(label: place.label, latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID)
        }
        profile.onboarded = true
        app.save()
        await app.replanNudges()
    }
}
