import Foundation

enum NoteDateInputError: LocalizedError {
    case invalidDate

    var errorDescription: String? {
        "Enter a valid date as d/m/yy or dd/mm/yyyy."
    }
}

enum NoteDateInput {
    static func todayText() -> String {
        text(for: Date())
    }

    static func text(for date: Date) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        return "\(parts.day!)/\(parts.month!)/\(parts.year!)"
    }

    static func shiftedText(_ input: String, by days: Int, today: Date = Date()) -> String? {
        guard let date = try? parse(input),
              let shifted = calendar.date(byAdding: .day, value: days, to: date),
              calendar.component(.year, from: shifted) >= 1000 else { return nil }
        if days > 0 && calendar.startOfDay(for: shifted) > calendar.startOfDay(for: today) {
            return nil
        }
        return text(for: shifted)
    }

    static func parse(_ input: String) throws -> Date {
        let parts = input.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 3,
              (1...2).contains(parts[0].count), (1...2).contains(parts[1].count),
              parts[2].count == 2 || parts[2].count == 4,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let day = Int(parts[0]), let month = Int(parts[1]), let enteredYear = Int(parts[2]) else {
            throw NoteDateInputError.invalidDate
        }

        let year = parts[2].count == 2 ? 2000 + enteredYear : enteredYear
        guard year >= 1000, (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(timeZone: calendar.timeZone,
                                                           year: year, month: month, day: day, hour: 12)) else {
            throw NoteDateInputError.invalidDate
        }
        let resolved = calendar.dateComponents([.day, .month, .year], from: date)
        guard resolved.day == day, resolved.month == month, resolved.year == year else {
            throw NoteDateInputError.invalidDate
        }
        return date
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
