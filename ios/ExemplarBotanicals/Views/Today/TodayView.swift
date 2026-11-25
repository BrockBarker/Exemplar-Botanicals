import SwiftUI
import SwiftData
import GardenCore

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \GardenProfile.created) private var profiles: [GardenProfile]
    @Query(sort: \Bed.created) private var beds: [Bed]
    @Query(sort: \Plant.created) private var plants: [Plant]
    @Query(sort: \JournalEntry.created) private var journal: [JournalEntry]

    @State private var showSettings = false
    @State private var detailNudge: Nudge?

    private var profile: GardenProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    greeting
                    WeatherCard(onSetLocation: { showSettings = true })
                    nudgeSection
                    bedSection
                }
                .padding(16)
            }
            .gardenBackground()
            .refreshable { await app.refresh(forceWeather: true) }
            .navigationTitle("Today")
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $detailNudge) { nudge in
                NudgeDetailView(nudge: nudge)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: app.focusedNudgeID, initial: true) { _, id in
                guard let id = id, let nudge = app.ledger.nudge(id: id) else { return }
                detailNudge = nudge
                app.focusedNudgeID = nil
            }
        }
    }

    private var greeting: some View {
        HStack(spacing: 12) {
            CoachAvatar(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var greetingText: String {
        let hour = app.calendar.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = profile?.gardenerName ?? ""
        return name.isEmpty ? "\(part)." : "\(part), \(name)."
    }

    private var subtitle: String {
        let count = inbox.count
        if count == 0 { return "Nothing needs you right now." }
        return count == 1 ? "One thing for today." : "\(count) things for today."
    }

    // MARK: Nudges

    private var inbox: [Nudge] { app.ledger.inbox(now: Date()) }
    private var upcoming: [Nudge] { app.ledger.upcoming(now: Date(), within: 36) }

    @ViewBuilder
    private var nudgeSection: some View {
        if !inbox.isEmpty {
            Text("For you")
                .font(.title3.bold())
                .onPhoto()
            ForEach(inbox) { nudge in
                NudgeCard(nudge: nudge, onOpen: { detailNudge = nudge })
            }
        }
        if !upcoming.isEmpty {
            Text("Coming up")
                .font(.title3.bold())
                .onPhoto()
            Card {
                ForEach(upcoming) { nudge in
                    Button {
                        detailNudge = nudge
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: nudge.kind.symbol)
                                .foregroundStyle(nudge.kind.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.title(for: nudge))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(whenText(nudge.fireDate, calendar: app.calendar))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if nudge.id != upcoming.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: Beds

    @ViewBuilder
    private var bedSection: some View {
        if beds.isEmpty {
            Card {
                Text("Add your beds and plants")
                    .font(.headline)
                Text("Watering, harvest and care nudges need to know what's growing where.")
                    .foregroundStyle(.secondary)
                Button("Go to Garden") { app.selectedTab = .garden }
                    .buttonStyle(.bordered)
            }
        } else {
            Text("Soil moisture")
                .font(.title3.bold())
                .onPhoto()
            Card {
                Text("Estimated from rain, evaporation and your watering log. Your finger test always wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(beds) { bed in
                    BedWaterRow(bed: bed, state: waterState(for: bed))
                    if bed.id != beds.last?.id { Divider() }
                }
            }
        }
    }

    private func waterState(for bed: Bed) -> WaterState {
        WaterModel.state(
            bed: bed.info,
            plants: plants.filter { $0.bedID == bed.id }.map { $0.info },
            journal: journal.map { $0.info },
            weather: app.weather,
            today: app.today,
            calendar: app.calendar
        )
    }
}

/// One bed's water estimate with quick buttons to log watering or a finger test.
struct BedWaterRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let bed: Bed
    let state: WaterState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.status.symbol)
                .foregroundStyle(state.status.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(bed.name)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Watered deeply (about an inch)") { logWater(WaterAmount.deep, "Deep watering") }
                Button("Watered lightly") { logWater(WaterAmount.light, "Light watering") }
                Section("Finger test, 2 inches down") {
                    ForEach(MoistureReading.allCases) { reading in
                        Button(reading.displayName) { logCheck(reading) }
                    }
                }
            } label: {
                Label("Log", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .accessibilityLabel("Log watering or a finger test for \(bed.name)")
        }
    }

    private var detail: String {
        switch state.status {
        case .unknown:
            return app.weather == nil ? "Waiting for weather" : "Do a finger test to start the estimate"
        default:
            var text = state.status.displayName
            if let last = state.lastRefillDay {
                text += " · last soaked \(dayText(last, calendar: app.calendar).lowercased())"
            }
            return text
        }
    }

    private func logWater(_ inches: Double, _ what: String) {
        let entry = JournalEntry(day: app.today, kind: .watering, what: what)
        entry.bedID = bed.id
        entry.bedName = bed.name
        entry.waterInches = inches
        context.insert(entry)
        app.save()
        Task { await app.replanNudges() }
    }

    private func logCheck(_ reading: MoistureReading) {
        let entry = JournalEntry(day: app.today, kind: .moistureCheck, what: "Finger test: \(reading.displayName.lowercased())")
        entry.bedID = bed.id
        entry.bedName = bed.name
        entry.moisture = reading
        context.insert(entry)
        app.save()
        Task { await app.replanNudges() }
    }
}
