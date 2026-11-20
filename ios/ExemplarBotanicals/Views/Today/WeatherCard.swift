import SwiftUI
import GardenCore

/// Current conditions and the week ahead.
struct WeatherCard: View {
    @Environment(AppModel.self) private var app
    var onSetLocation: () -> Void

    var body: some View {
        Card {
            if let weather = app.weather {
                current(weather)
                week(weather)
                if let message = app.weatherMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if GardenRepository.existingProfile(app.context)?.hasLocation ?? false {
                HStack {
                    ProgressView()
                    Text(app.weatherMessage ?? "Getting your forecast...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Set your garden's location")
                    .font(.headline)
                Text("Frost, heat, dry-spell and spraying nudges all come from your local forecast.")
                    .foregroundStyle(.secondary)
                Button("Set location", action: onSetLocation)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func current(_ weather: WeatherReport) -> some View {
        let today = weather.day(app.today)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: OpenMeteo.symbol(code: weather.current?.weatherCode ?? today?.weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                if let temp = weather.current?.tempF {
                    Text(NudgeText.temp(temp))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Text(OpenMeteo.describe(code: weather.current?.weatherCode ?? today?.weatherCode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let hi = today?.highF, let lo = today?.lowF {
                    Text("H \(Int(hi.rounded()))°  L \(Int(lo.rounded()))°")
                        .font(.subheadline.weight(.semibold))
                }
                if let chance = today?.rainChance {
                    Text("Rain \(Int(chance.rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(GardenRepository.existingProfile(app.context)?.locationLabel ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func week(_ weather: WeatherReport) -> some View {
        let days = weather.days(from: app.today, through: app.today.adding(days: 6, calendar: app.calendar))
        return HStack(spacing: 0) {
            ForEach(days, id: \.day) { day in
                VStack(spacing: 4) {
                    Text(shortName(day.day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: OpenMeteo.symbol(code: day.weatherCode))
                        .symbolRenderingMode(.multicolor)
                        .frame(height: 20)
                    Text(day.highF.map { "\(Int($0.rounded()))°" } ?? "–")
                        .font(.caption.weight(.semibold))
                    Text(day.lowF.map { "\(Int($0.rounded()))°" } ?? "–")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(rainText(day))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func shortName(_ day: LocalDay) -> String {
        if day == app.today { return "Today" }
        let formatter = DateFormatter()
        formatter.timeZone = app.calendar.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: day.date(atMinute: 12 * 60, in: app.calendar))
    }

    private func rainText(_ day: DailyWeather) -> String {
        guard let rain = day.rainInches, rain >= 0.05 else { return " " }
        return String(format: "%.1f\"", rain)
    }
}
