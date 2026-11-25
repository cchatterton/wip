import Foundation

struct Organisation: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var aliases: [String] = []
}

struct Contact: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var aliases: [String] = []
    var organisationID: UUID?

    var matchTerms: [String] { [name] + aliases }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, organisationID
    }

    init(id: UUID = UUID(), name: String, aliases: [String] = [], organisationID: UUID? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.organisationID = organisationID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        organisationID = try container.decodeIfPresent(UUID.self, forKey: .organisationID)
    }
}

struct Note: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var body: String
    var organisationID: UUID?
    var contactIDs: [UUID] = []
    var sourceID: UUID?
}

struct SourceImport: Identifiable, Codable, Sendable {
    var id = UUID()
    var date: Date
    var rawText: String
    var expectedSections: Int?
    var createdAt = Date()
}

enum TaskLane: String, CaseIterable, Codable, Sendable {
    case now = "Now"
    case next = "Next"
    case later = "Later"
}

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var lane: TaskLane = .now
    var order: Int = 0
    var originOrganisationID: UUID?
    var originContactID: UUID?
    var completedAt: Date?

    func isVisible(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let completedAt else { return true }
        return calendar.isDate(completedAt, inSameDayAs: date)
    }
}

struct AppData: Codable, Sendable {
    var organisations: [Organisation] = []
    var contacts: [Contact] = []
    var notes: [Note] = []
    var imports: [SourceImport] = []
    var tasks: [TaskItem] = []
}

struct ParsedSection {
    var organisationID: UUID?
    var body: String
}

struct ParseResult {
    var sections: [ParsedSection]
    var matchedHeadings: Int
}

enum NoteParser {
    static func parse(_ text: String, organisations: [Organisation], inheritedOrganisationID: UUID? = nil) -> ParseResult {
        var sections: [ParsedSection] = []
        var lines: [String] = []
        var currentOrganisationID = inheritedOrganisationID
        var matchedHeadings = 0

        func flush() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(ParsedSection(organisationID: currentOrganisationID, body: body))
            }
            lines.removeAll()
        }

        for line in text.components(separatedBy: .newlines) {
            if let organisation = organisationForHeading(line, in: organisations) {
                flush()
                currentOrganisationID = organisation.id
                matchedHeadings += 1
            } else {
                lines.append(line)
            }
        }
        flush()
        return ParseResult(sections: sections, matchedHeadings: matchedHeadings)
    }

    static func organisationForHeading(_ line: String, in organisations: [Organisation]) -> Organisation? {
        var heading = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if heading.hasSuffix(":") { heading.removeLast() }
        heading = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else { return nil }
        return organisations.first { organisation in
            ([organisation.name] + organisation.aliases).contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).compare(heading, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }

    static func contacts(in text: String, from contacts: [Contact]) -> [UUID] {
        contacts.filter { contains($0, in: text) }.map(\.id)
    }

    static func contains(_ contact: Contact, in text: String) -> Bool {
        contact.matchTerms.contains { containsName($0, in: text) }
    }

    static func containsName(_ name: String, in text: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: trimmed) + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func organisationIDs(in text: String, from organisations: [Organisation]) -> Set<UUID> {
        Set(organisations.filter { organisation in
            ([organisation.name] + organisation.aliases).contains { containsName($0, in: text) }
        }.map(\.id))
    }
}
