import Foundation

public enum MarketStatus: String, Sendable {
    case preOpen, open, closed, holiday

    public var label: String {
        switch self {
        case .preOpen: "Pre-open"
        case .open: "Market open"
        case .closed: "Market closed"
        case .holiday: "Market holiday"
        }
    }
}

/// NSE trading calendar in IST. Holidays are passed in (bundled list, updated yearly).
public struct MarketCalendar: Sendable {
    public static let ist = TimeZone(identifier: "Asia/Kolkata")!

    public var calendar: Calendar
    public let holidays: Set<DateComponents>

    public init(holidays: [DateComponents] = []) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.ist
        calendar = cal
        self.holidays = Set(holidays.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) })
    }

    public func isTradingDay(_ date: Date) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard c.weekday != 1, c.weekday != 7 else { return false }
        return !holidays.contains(DateComponents(year: c.year, month: c.month, day: c.day))
    }

    public func status(at date: Date) -> MarketStatus {
        guard isTradingDay(date) else {
            let weekday = calendar.component(.weekday, from: date)
            return weekday == 1 || weekday == 7 ? .closed : .holiday
        }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        switch minutes {
        case (9 * 60)..<(9 * 60 + 15): return .preOpen
        case (9 * 60 + 15)..<(15 * 60 + 30): return .open
        default: return .closed
        }
    }

    /// The trading day live figures belong to: today once the market has opened, otherwise the last trading day.
    public func sessionDay(at date: Date) -> Date {
        let opened = isTradingDay(date) && (status(at: date) == .open || calendar.component(.hour, from: date) >= 15)
        return opened ? calendar.startOfDay(for: date) : previousTradingDay(before: date)
    }

    /// Most recent trading day strictly before `date`.
    public func previousTradingDay(before date: Date) -> Date {
        var day = calendar.startOfDay(for: date)
        repeat { day = calendar.date(byAdding: .day, value: -1, to: day)! } while !isTradingDay(day)
        return day
    }
}
