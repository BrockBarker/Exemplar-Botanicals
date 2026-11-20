import SwiftUI
import SwiftData
import GardenCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GardenProfile.created) private var profiles: [GardenProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    SettingsForm(profile: profile)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsForm: View {
    @Environment(AppModel.self) private var app
    @Bindable var profile: GardenProfile

    @State private var placeQuery = ""
    @State private var locating = false
    @State private var locationMessage: String?
    @State private var locationService = LocationService()
    @State private var budgetText = ""
    @State private var confirmErase = false
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            coachSection
            gardenerSection
            locationSection
            nudgeSection
            Section {
                Button("Erase everything on this phone", role: .destructive) { confirmErase = true }
            } footer: {
                Text("Your garden lives only on this phone. Erasing removes beds, plants, the journal, chats and settings.")
            }
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .onAppear {
            budgetText = profile.monthlyBudget.map { String(format: "%g", $0) } ?? ""
            Task { await app.checkHealth() }
        }
        .onDisappear {
            app.save()
            Task { await app.replanNudges() }
        }
        .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { app.eraseAll() }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: Coach

    private var coachSection: some View {
        Section {
            HStack(spacing: 12) {
                CoachAvatar(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.coachName)
                        .font(.headline)
                    Text(coachStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if app.voiceAvailable {
                Toggle("Read replies aloud in \(app.coachName)'s voice", isOn: $profile.voiceEnabled)
            }
            NavigationLink("About the coach") {
                CoachAboutView()
            }
        } header: {
            Text("Coach")
        } footer: {
            if !app.voiceAvailable && !app.isDemo {
                Text("\(app.coachName)'s voice turns on here once it's set up on the server.")
            }
        }
    }

    private var coachStatus: String {
        if app.isDemo { return "Demo mode (not connected)" }
        if let message = app.healthMessage { return message }
        guard let health = app.health else { return "Checking..." }
        if health.claudeConfigured == false { return "Server is up but missing its Claude key" }
        let placeholders = (health.persona ?? []).filter { $0.status == "placeholder" }.count
        return placeholders > 0 ? "Connected · \(placeholders) persona files still placeholders" : "Connected"
    }

    // MARK: You

    private var gardenerSection: some View {
        Section {
            TextField("Your first name", text: $profile.gardenerName)
            HStack {
                Text("Monthly budget")
                Spacer()
                TextField("$", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onChange(of: budgetText) { _, text in
                        profile.monthlyBudget = Double(text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces))
                    }
            }
            TextField("Budget notes (optional)", text: $profile.budgetNotes)
            Toggle("Leave diluted urine out of suggestions", isOn: $profile.avoidUrine)
        } header: {
            Text("You")
        }
    }

    // MARK: Location

    private var locationSection: some View {
        Section {
            LabeledContent("Garden", value: profile.locationLabel.isEmpty ? "Not set" : profile.locationLabel)
            HStack {
                TextField("Town or ZIP code", text: $placeQuery)
                    .submitLabel(.search)
                    .onSubmit { Task { await find() } }
                Button("Find") { Task { await find() } }
                    .disabled(placeQuery.trimmingCharacters(in: .whitespaces).isEmpty || locating)
            }
            Button {
                Task { await useCurrent() }
            } label: {
                Label("Use my current location", systemImage: "location")
            }
            .disabled(locating)
            if let message = locationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("USDA hardiness zone (e.g. 7a)", text: $profile.usdaZone)
            FrostDateRow(title: "Last spring frost", value: $profile.lastSpringFrost, calendar: app.calendar)
            FrostDateRow(title: "First fall frost", value: $profile.firstFallFrost, calendar: app.calendar)
        } header: {
            Text("Location")
        } footer: {
            Text("Zone and frost dates are optional; they help the coach with timing. Your county Extension office or a seed catalog lists them.")
        }
    }

    private func find() async {
        locating = true
        defer { locating = false }
        do {
            let place = try await locationService.place(named: placeQuery)
            await app.setLocation(label: place.label, latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID)
            locationMessage = "Set to \(place.label)."
            placeQuery = ""
        } catch {
            locationMessage = error.localizedDescription
        }
    }

    private func useCurrent() async {
        locating = true
        defer { locating = false }
        do {
            let place = try await locationService.currentPlace()
            await app.setLocation(label: place.label, latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID)
            locationMessage = "Set to \(place.label)."
        } catch {
            locationMessage = error.localizedDescription
        }
    }

    // MARK: Nudges

    private var nudgeSection: some View {
        Section {
            Toggle("Send nudges", isOn: Binding(
                get: { profile.nudgesEnabled },
                set: { on in
                    profile.nudgesEnabled = on
                    if on {
                        Task {
                            let allowed = await NotificationScheduler.requestPermission()
                            if !allowed {
                                profile.nudgesEnabled = false
                                notificationsDenied = true
                            }
                        }
                    }
                }
            ))
            if notificationsDenied {
                Text("Notifications are off for this app. Turn them on in the iPhone Settings app under Notifications.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if profile.nudgesEnabled {
                Stepper("At most \(profile.maxNudgesPerDay) a day", value: $profile.maxNudgesPerDay, in: 1...4)
                DatePicker("Quiet from", selection: minuteBinding(\.quietStartMinute), displayedComponents: .hourAndMinute)
                DatePicker("Quiet until", selection: minuteBinding(\.quietEndMinute), displayedComponents: .hourAndMinute)
                DatePicker("Routine nudges at", selection: minuteBinding(\.deliveryMinute), displayedComponents: .hourAndMinute)
                Stepper("Foliar spray every \(profile.foliarIntervalDays) days", value: $profile.foliarIntervalDays, in: 7...28)
            }
        } header: {
            Text("Nudges")
        } footer: {
            Text("Frost and heat warnings still respect quiet hours; they're timed for the afternoon or morning before.")
        }
    }

    private func minuteBinding(_ keyPath: ReferenceWritableKeyPath<GardenProfile, Int>) -> Binding<Date> {
        Binding(
            get: { dateForMinute(profile[keyPath: keyPath]) },
            set: { profile[keyPath: keyPath] = minuteForDate($0) }
        )
    }
}

/// An optional date stored as "YYYY-MM-DD".
private struct FrostDateRow: View {
    let title: String
    @Binding var value: String?
    let calendar: Calendar

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { value != nil },
            set: { on in value = on ? (value ?? LocalDay(Date(), calendar: calendar).string) : nil }
        ))
        if let current = value, let day = LocalDay(current) {
            DatePicker(
                "Date",
                selection: Binding(
                    get: { day.date(atMinute: 12 * 60, in: calendar) },
                    set: { value = LocalDay($0, calendar: calendar).string }
                ),
                displayedComponents: .date
            )
        }
    }
}

struct CoachAboutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    CoachAvatar(size: 96)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                Text("The coach is an AI built from \(app.coachName)'s gardening advice, opinions and way of talking. \(app.coachName) isn't reading your chats, and the coach will say so if you ask.")
                Text("Advice is strictly organic. Suggestions start with what you already have, then free options like compost, leaves, kitchen scraps or diluted urine, then low-cost ones, and only then products to buy, with typical prices.")
                Text("Photo checks look for water stress and nutrient problems. When it's hard to tell, the coach says so and may suggest a soil test.")
            }
            Section("Privacy") {
                Text("Your garden records stay on this phone. When you chat or check a photo, the question, the photo and a summary of your garden (beds, plants, recent journal, rounded location and weather) are sent to the coach server to get an answer. Nothing is used for ads, and there are no accounts.")
            }
            if let health = app.health, let persona = health.persona, !persona.isEmpty {
                Section("Persona files on the server") {
                    ForEach(persona, id: \.name) { file in
                        LabeledContent(file.name, value: file.status)
                    }
                }
            }
        }
        .navigationTitle("About the coach")
    }
}
