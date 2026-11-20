import SwiftUI
import UIKit
import GardenCore

/// David's photo (Assets: CoachAvatar), clipped to a circle.
struct CoachAvatar: View {
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = UIImage(named: "CoachAvatar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A rounded card used on the Today screen.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A small colored label, e.g. a tier or a water status.
struct Chip: View {
    var text: String
    var color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = symbol {
                Image(systemName: symbol)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

extension Tier {
    var color: Color {
        switch self {
        case .owned: return .green
        case .free: return .teal
        case .lowCost: return .blue
        case .branded: return .purple
        }
    }
}

extension WaterStatus {
    var color: Color {
        switch self {
        case .ok: return .green
        case .check: return .orange
        case .dry: return .red
        case .unknown: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "drop.fill"
        case .check: return "hand.point.down.fill"
        case .dry: return "drop.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

extension NudgeKind {
    var color: Color {
        switch self {
        case .frost: return .blue
        case .heatStress, .drySpell: return .orange
        case .waterNow, .moistureCheck: return .teal
        case .wind, .staking: return .brown
        case .foliar, .firstFeed, .feed: return .green
        }
    }
}

extension View {
    /// Hides the keyboard when the user scrolls or taps outside a field.
    func dismissKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}

/// "7:30 AM"
func timeText(_ minute: Int) -> String {
    let h = minute / 60
    let m = minute % 60
    let h12 = h % 12 == 0 ? 12 : h % 12
    return String(format: "%ld:%02ld %@", h12, m, h < 12 ? "AM" : "PM")
}

/// A Date for a minute-of-day, for DatePicker bindings.
func dateForMinute(_ minute: Int) -> Date {
    Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
}

func minuteForDate(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// "Today, 7:30 AM", "Tomorrow, 4 PM" or "Thu, 7:30 AM".
func whenText(_ date: Date, calendar: Calendar) -> String {
    let today = LocalDay(Date(), calendar: calendar)
    let day = LocalDay(date, calendar: calendar)
    let offset = today.days(to: day, calendar: calendar)
    let formatter = DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "h:mm a"
    let time = formatter.string(from: date)
    switch offset {
    case 0: return "Today, \(time)"
    case 1: return "Tomorrow, \(time)"
    case -1: return "Yesterday, \(time)"
    default:
        formatter.dateFormat = "EEE, h:mm a"
        return formatter.string(from: date)
    }
}

/// "Tue, Jul 14" for a LocalDay.
func dayText(_ day: LocalDay, calendar: Calendar) -> String {
    let today = LocalDay(Date(), calendar: calendar)
    switch today.days(to: day, calendar: calendar) {
    case 0: return "Today"
    case -1: return "Yesterday"
    case 1: return "Tomorrow"
    default:
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day.date(atMinute: 12 * 60, in: calendar))
    }
}
