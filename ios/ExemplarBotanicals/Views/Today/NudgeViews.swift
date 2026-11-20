import SwiftUI
import GardenCore

/// A nudge that went out and still needs attention.
struct NudgeCard: View {
    @Environment(AppModel.self) private var app
    let nudge: Nudge
    var onOpen: () -> Void

    var body: some View {
        Card {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: nudge.kind.symbol)
                        .font(.title3)
                        .foregroundStyle(nudge.kind.color)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.title(for: nudge))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(app.body(for: nudge))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(whenText(nudge.fireDate, calendar: app.calendar))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            NudgeActions(nudge: nudge, compact: true)
        }
    }
}

/// Done / finger-test readings, snooze, and "Ask David".
struct NudgeActions: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let nudge: Nudge
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nudge.kind == .moistureCheck {
                Text("How does the soil feel 2 inches down?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(MoistureReading.allCases) { reading in
                        Button(reading.displayName) {
                            app.complete(nudge, moisture: reading)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
            HStack(spacing: 8) {
                if nudge.kind != .moistureCheck {
                    Button {
                        app.complete(nudge)
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Menu {
                    Button("In 3 hours") { snooze(hours: 3) }
                    Button("Tomorrow morning") { snoozeTomorrow() }
                    Button("Dismiss", role: .destructive) {
                        app.dismiss(nudge)
                        dismiss()
                    }
                } label: {
                    Label("Later", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                Button {
                    app.askCoach(about: nudge)
                    dismiss()
                } label: {
                    Label(compact ? "Ask" : "Ask \(app.coachName)", systemImage: "bubble.left")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
    }

    private func snooze(hours: Double) {
        app.snooze(nudge, until: Date().addingTimeInterval(hours * 3600))
        dismiss()
    }

    private func snoozeTomorrow() {
        let profile = GardenRepository.profile(app.context)
        let tomorrow = app.today.adding(days: 1, calendar: app.calendar)
        app.snooze(nudge, until: tomorrow.date(atMinute: profile.deliveryMinute, in: app.calendar))
        dismiss()
    }
}

/// The full explanation behind a nudge, with options in use-what-you-have order.
struct NudgeDetailView: View {
    @Environment(AppModel.self) private var app
    let nudge: Nudge

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: nudge.kind.symbol)
                            .font(.title2)
                            .foregroundStyle(nudge.kind.color)
                        Text(nudge.kind.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(whenText(nudge.fireDate, calendar: app.calendar))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(app.title(for: nudge))
                        .font(.title2.bold())
                    Text(app.body(for: nudge))
                        .font(.body)
                    if !nudge.detail.isEmpty {
                        Divider()
                        Text(nudge.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !isPast {
                        Text("This one is scheduled. Doing it now? Tap Done and it won't be sent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    NudgeActions(nudge: nudge)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var isPast: Bool { nudge.fireDate <= Date() }
}
