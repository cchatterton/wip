import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct NoteArchive: Codable {
    static let formatName = "WIP notes"
    let format: String
    let version: Int
    let search: String?
    let notes: [Record]

    struct Record: Codable {
        let date: String
        let organisation: String?
        let body: String
    }

    init(notes: [Note], organisations: [Organisation], search: String) {
        format = Self.formatName
        version = 1
        self.search = search
        self.notes = notes.map { note in
            Record(date: Self.dateFormatter.string(from: note.date),
                   organisation: organisations.first(where: { $0.id == note.organisationID })?.name,
                   body: note.body)
        }
    }

    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    static func parseDate(_ value: String) throws -> Date {
        let formatter = dateFormatter
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw NoteArchiveError.invalidDate(value)
        }
        return date
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

enum NoteArchiveError: LocalizedError {
    case invalidFormat
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "This is not a supported WIP notes JSON file."
        case .invalidDate(let value): return "The JSON file contains an invalid date: \(value)."
        }
    }
}

struct NoteArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw NoteArchiveError.invalidFormat
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
