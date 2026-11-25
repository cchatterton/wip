import Combine
import Foundation

enum WIPError: LocalizedError {
    case emptyName
    case duplicateName
    case emptyText
    case futureNoteDate
    case duplicateNote
    case mergeNeedsSameOrganisation
    case processing

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name first."
        case .duplicateName: return "That name or alias is already in use."
        case .emptyText: return "Enter some text first."
        case .futureNoteDate: return "Notes must be dated today or earlier."
        case .duplicateNote: return "That note is already saved for this organisation and date."
        case .mergeNeedsSameOrganisation: return "Select notes from the same organisation to merge them."
        case .processing: return "Please wait for note processing to finish."
        }
    }
}

@MainActor
final class WIPStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var now = Date()
    @Published var errorMessage: String?
    @Published var processingMessage: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WIP", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("WIP.json")
        }
        if let bytes = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: bytes) {
            data = decoded
        } else {
            data = AppData()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Could not save WIP data: \(error.localizedDescription)"
        }
    }

    private func validateOrganisation(_ name: String, aliases: [String], excluding id: UUID? = nil) throws {
        let allNames = ([name] + aliases).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WIPError.emptyName }
        let normalized = allNames.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        guard Set(normalized).count == normalized.count else { throw WIPError.duplicateName }
        for organisation in data.organisations where organisation.id != id {
            let existing = ([organisation.name] + organisation.aliases)
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            if normalized.contains(where: { existing.contains($0) }) { throw WIPError.duplicateName }
        }
    }

    @discardableResult
    func addOrganisation(name: String) async throws -> UUID {
        guard processingMessage == nil else { throw WIPError.processing }
        try validateOrganisation(name, aliases: [])
        let organisation = Organisation(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        var updated = data
        updated.organisations.append(organisation)
        updated.organisations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        await commitReprocessed(updated)
        return organisation.id
    }

    func updateOrganisation(id: UUID, name: String, aliasesCSV: String) async throws {
        guard processingMessage == nil else { throw WIPError.processing }
        let aliases = aliasesCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        try validateOrganisation(name, aliases: aliases, excluding: id)
        var updated = data
        guard let index = updated.organisations.firstIndex(where: { $0.id == id }) else { return }
        updated.organisations[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.organisations[index].aliases = aliases
        updated.organisations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        await commitReprocessed(updated)
    }

    func deleteOrganisation(id: UUID) async {
        guard processingMessage == nil else { return }
        var updated = data
        updated.organisations.removeAll { $0.id == id }
        updated.contacts = updated.contacts.map { contact in
            var updated = contact
            if updated.organisationID == id { updated.organisationID = nil }
            return updated
        }
        updated.tasks = updated.tasks.map { task in
            var updated = task
            if updated.originOrganisationID == id { updated.originOrganisationID = nil }
            return updated
        }
        await commitReprocessed(updated)
    }

    @discardableResult
    func addContact(name: String) async throws -> UUID {
        guard processingMessage == nil else { throw WIPError.processing }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateContact(name, aliases: [])
        let contact = Contact(name: name)
        var updated = data
        updated.contacts.append(contact)
        updated.contacts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        await commitReprocessed(updated)
        return contact.id
    }

    func updateContact(id: UUID, name: String, aliasesCSV: String, organisationID: UUID?) async throws {
        guard processingMessage == nil else { throw WIPError.processing }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = aliasesCSV.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        try validateContact(name, aliases: aliases, excluding: id)
        var updated = data
        guard let index = updated.contacts.firstIndex(where: { $0.id == id }) else { return }
        updated.contacts[index].name = name
        updated.contacts[index].aliases = aliases
        updated.contacts[index].organisationID = organisationID
        updated.contacts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        await commitReprocessed(updated)
    }

    private func validateContact(_ name: String, aliases: [String], excluding id: UUID? = nil) throws {
        guard !name.isEmpty else { throw WIPError.emptyName }
        let normalized = ([name] + aliases).map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        guard Set(normalized).count == normalized.count else { throw WIPError.duplicateName }
        for contact in data.contacts where contact.id != id {
            let existing = contact.matchTerms.map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
            if normalized.contains(where: { existing.contains($0) }) { throw WIPError.duplicateName }
        }
    }

    func deleteContact(id: UUID) async {
        guard processingMessage == nil else { return }
        var updated = data
        updated.contacts.removeAll { $0.id == id }
        updated.tasks = updated.tasks.map { task in
            var updated = task
            if updated.originContactID == id { updated.originContactID = nil }
            return updated
        }
        await commitReprocessed(updated)
    }

    @discardableResult
    func importNotes(text: String, date: Date, expectedSections: Int?) throws -> Int {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WIPError.emptyText }
        try validateNoteDate(date)
        let source = SourceImport(date: date, rawText: text, expectedSections: expectedSections)
        let result = NoteParser.parse(text, organisations: data.organisations)
        var newNotes: [Note] = []
        var duplicatesSkipped = 0
        for section in result.sections {
            if isDuplicateNote(body: section.body, date: date, organisationID: section.organisationID,
                               additionalNotes: newNotes) {
                duplicatesSkipped += 1
            } else {
                newNotes.append(Note(date: date, body: section.body, organisationID: section.organisationID,
                                     contactIDs: NoteParser.contacts(in: section.body, from: data.contacts), sourceID: source.id))
            }
        }
        guard !newNotes.isEmpty else { throw WIPError.duplicateNote }
        data.imports.append(source)
        data.notes.append(contentsOf: newNotes)
        persist()
        return duplicatesSkipped
    }

    func previewImport(text: String) -> ParseResult {
        NoteParser.parse(text, organisations: data.organisations)
    }

    func importNoteArchive(_ bytes: Data) throws -> (added: Int, skipped: Int, search: String) {
        let archive = try JSONDecoder().decode(NoteArchive.self, from: bytes)
        guard archive.format == NoteArchive.formatName, archive.version == 1 else {
            throw NoteArchiveError.invalidFormat
        }

        var organisations = data.organisations
        var imported: [Note] = []
        var skipped = 0
        for record in archive.notes {
            let date = try NoteArchive.parseDate(record.date)
            try validateNoteDate(date)
            let body = record.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { throw WIPError.emptyText }

            var organisationID: UUID?
            if let name = record.organisation?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                if let existing = organisations.first(where: { organisation in
                    ([organisation.name] + organisation.aliases).contains {
                        $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    }
                }) {
                    organisationID = existing.id
                } else {
                    let organisation = Organisation(name: name)
                    organisations.append(organisation)
                    organisationID = organisation.id
                }
            }

            if isDuplicateNote(body: body, date: date, organisationID: organisationID,
                               additionalNotes: imported) {
                skipped += 1
            } else {
                imported.append(Note(date: date, body: body, organisationID: organisationID,
                                     contactIDs: NoteParser.contacts(in: body, from: data.contacts)))
            }
        }

        if !imported.isEmpty {
            data.organisations = organisations.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            data.notes.append(contentsOf: imported)
            persist()
        }
        let savedSearch = archive.search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackDate = try archive.notes.first.map { NoteDateInput.text(for: try NoteArchive.parseDate($0.date)) } ?? ""
        return (imported.count, skipped, savedSearch.isEmpty ? fallbackDate : savedSearch)
    }

    func updateNote(id: UUID, date: Date, body: String, organisationID: UUID?) throws {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw WIPError.emptyText }
        try validateNoteDate(date)
        guard let index = data.notes.firstIndex(where: { $0.id == id }) else { return }
        let sections = NoteParser.parse(body, organisations: data.organisations,
                                        inheritedOrganisationID: organisationID).sections
        guard !sections.isEmpty else { throw WIPError.emptyText }
        var replacements: [Note] = []
        for (offset, section) in sections.enumerated() {
            if isDuplicateNote(body: section.body, date: date, organisationID: section.organisationID,
                               excluding: [id], additionalNotes: replacements) {
                throw WIPError.duplicateNote
            }
            var note = data.notes[index]
            if offset > 0 { note.id = UUID() }
            note.date = date
            note.body = section.body
            note.organisationID = section.organisationID
            note.contactIDs = NoteParser.contacts(in: section.body, from: data.contacts)
            replacements.append(note)
        }
        data.notes.remove(at: index)
        data.notes.append(contentsOf: replacements)
        persist()
    }

    private func validateNoteDate(_ date: Date) throws {
        if Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date()) {
            throw WIPError.futureNoteDate
        }
    }

    private func isDuplicateNote(body: String, date: Date, organisationID: UUID?,
                                 excluding excludedIDs: Set<UUID> = [], additionalNotes: [Note] = []) -> Bool {
        let candidate = duplicateKey(body)
        return (data.notes + additionalNotes).contains { note in
            !excludedIDs.contains(note.id) && note.organisationID == organisationID &&
            Calendar.current.isDate(note.date, inSameDayAs: date) && duplicateKey(note.body) == candidate
        }
    }

    private func duplicateKey(_ body: String) -> String {
        body.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteNotes(ids: Set<UUID>) {
        data.notes.removeAll { ids.contains($0.id) }
        persist()
    }

    func mergeNotes(ids: Set<UUID>) throws {
        let selected = data.notes.filter { ids.contains($0.id) }.sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return $0.date > $1.date
        }
        guard selected.count > 1 else { return }
        guard Set(selected.map(\.organisationID)).count == 1 else { throw WIPError.mergeNeedsSameOrganisation }
        var merged = selected[0]
        merged.body = selected.map(\.body).joined(separator: "\n\n")
        merged.contactIDs = NoteParser.contacts(in: merged.body, from: data.contacts)
        if isDuplicateNote(body: merged.body, date: merged.date, organisationID: merged.organisationID,
                           excluding: ids) {
            throw WIPError.duplicateNote
        }
        data.notes.removeAll { ids.contains($0.id) }
        data.notes.append(merged)
        persist()
    }

    private func commitReprocessed(_ updated: AppData) async {
        processingMessage = "Processing notes…"
        await Task.yield()
        let rebuilt = await Task.detached(priority: .userInitiated) {
            Self.rebuiltNotes(updated.notes, organisations: updated.organisations, contacts: updated.contacts)
        }.value
        var completed = updated
        completed.notes = rebuilt
        data = completed
        persist()
        processingMessage = nil
    }

    nonisolated private static func rebuiltNotes(_ notes: [Note], organisations: [Organisation],
                                                  contacts: [Contact]) -> [Note] {
        var rebuilt: [Note] = []
        for note in notes {
            let result = NoteParser.parse(note.body, organisations: organisations,
                                          inheritedOrganisationID: organisations.contains(where: { $0.id == note.organisationID }) ? note.organisationID : nil)
            if result.sections.isEmpty { continue }
            for (offset, section) in result.sections.enumerated() {
                var part = note
                if offset > 0 { part.id = UUID() }
                part.body = section.body
                part.organisationID = section.organisationID
                part.contactIDs = NoteParser.contacts(in: section.body, from: contacts)
                rebuilt.append(part)
            }
        }
        return rebuilt
    }

    func addTask(text: String, lane: TaskLane = .now, organisationID: UUID? = nil, contactID: UUID? = nil) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WIPError.emptyText }
        let nextOrder = (data.tasks.filter { $0.lane == lane }.map(\.order).max() ?? -1) + 1
        data.tasks.append(TaskItem(text: text, lane: lane, order: nextOrder,
                                   originOrganisationID: organisationID, originContactID: contactID))
        persist()
    }

    func toggleTask(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].completedAt = data.tasks[index].completedAt == nil ? Date() : nil
        now = Date()
        persist()
    }

    func updateTask(_ id: UUID, text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WIPError.emptyText }
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].text = text
        persist()
    }

    func deleteTask(_ id: UUID) {
        data.tasks.removeAll { $0.id == id }
        persist()
    }

    func tasks(forOrganisation id: UUID) -> [TaskItem] {
        data.tasks.filter { task in
            task.isVisible(on: now) &&
            (task.originOrganisationID == id || NoteParser.organisationIDs(in: task.text, from: data.organisations).contains(id))
        }.sorted(by: taskOrder)
    }

    func tasks(forContact id: UUID) -> [TaskItem] {
        guard let contact = data.contacts.first(where: { $0.id == id }) else { return [] }
        return data.tasks.filter { task in
            task.isVisible(on: now) &&
            (task.originContactID == id || NoteParser.contains(contact, in: task.text))
        }.sorted(by: taskOrder)
    }

    private func taskOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.lane != b.lane { return TaskLane.allCases.firstIndex(of: a.lane)! < TaskLane.allCases.firstIndex(of: b.lane)! }
        if a.order != b.order { return a.order < b.order }
        return a.id.uuidString < b.id.uuidString
    }

    func moveTask(_ id: UUID, to lane: TaskLane, before targetID: UUID? = nil) {
        guard let dragged = data.tasks.first(where: { $0.id == id }) else { return }
        if targetID == id { return }
        var laneTasks = data.tasks.filter { $0.lane == lane && $0.id != id }.sorted(by: taskOrder)
        let insertAt = targetID.flatMap { target in laneTasks.firstIndex(where: { $0.id == target }) } ?? laneTasks.count
        var moved = dragged
        moved.lane = lane
        laneTasks.insert(moved, at: insertAt)
        for (order, task) in laneTasks.enumerated() {
            if let index = data.tasks.firstIndex(where: { $0.id == task.id }) {
                data.tasks[index].lane = lane
                data.tasks[index].order = order
            }
        }
        persist()
    }
}
