import Foundation

@main
struct WIPStoreChecks {
    @MainActor
    static func main() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WIPStoreChecks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = WIPStore(fileURL: fileURL)

        let shortDate = try NoteDateInput.parse("1/2/26")
        let longDate = try NoteDateInput.parse("01/02/2026")
        precondition(Calendar.current.isDate(shortDate, inSameDayAs: longDate))
        precondition((try? NoteDateInput.parse("29/2/24")) != nil)
        precondition((try? NoteDateInput.parse("31/2/26")) == nil)
        precondition((try? NoteDateInput.parse("1/2/6")) == nil)

        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        try store.importNotes(text: "A note from today.", date: today, expectedSections: nil)
        precondition(store.data.notes.count == 1)

        do {
            try store.importNotes(text: "A future note.", date: tomorrow, expectedSections: nil)
            fatalError("Future import was accepted")
        } catch WIPError.futureNoteDate { }
        precondition(store.data.notes.count == 1)

        let note = store.data.notes[0]
        do {
            try store.updateNote(id: note.id, date: tomorrow, body: "Changed", organisationID: nil)
            fatalError("Future edit was accepted")
        } catch WIPError.futureNoteDate { }
        precondition(store.data.notes[0].body == note.body)

        do {
            try store.importNotes(text: "  A  NOTE FROM TODAY.  ", date: today, expectedSections: nil)
            fatalError("Duplicate import was accepted")
        } catch WIPError.duplicateNote { }
        precondition(store.data.notes.count == 1)

        try store.importNotes(text: "A note from today with an added detail.", date: today, expectedSections: nil)
        precondition(store.data.notes.count == 2)
        let distinctNote = store.data.notes[1]
        do {
            try store.updateNote(id: distinctNote.id, date: today, body: note.body, organisationID: nil)
            fatalError("Duplicate edit was accepted")
        } catch WIPError.duplicateNote { }

        let organisationID = try await store.addOrganisation(name: "Example Organisation")
        let secondOrganisationID = try await store.addOrganisation(name: "Another Organisation")
        try store.importNotes(text: "Example Organisation\nA repeated section.", date: today, expectedSections: nil)
        let skipped = try store.importNotes(
            text: "Example Organisation\nA repeated section.\nAnother Organisation\nA new section.",
            date: today, expectedSections: nil)
        precondition(skipped == 1)
        precondition(store.data.notes.contains { $0.organisationID == secondOrganisationID && $0.body == "A new section." })
        try store.addTask(text: "First", organisationID: organisationID)
        try store.addTask(text: "Second", organisationID: organisationID)
        try store.addTask(text: "Later", lane: .next, organisationID: organisationID)
        let first = store.data.tasks.first { $0.text == "First" }!
        let second = store.data.tasks.first { $0.text == "Second" }!
        let later = store.data.tasks.first { $0.text == "Later" }!

        store.moveTask(second.id, to: .now, before: first.id)
        precondition(store.tasks(forOrganisation: organisationID).filter { $0.lane == .now }.map(\.text) == ["Second", "First"])

        store.moveTask(first.id, to: .next, before: later.id)
        precondition(store.tasks(forOrganisation: organisationID).filter { $0.lane == .next }.map(\.text) == ["First", "Later"])

        let legacyContactJSON = """
        {"id":"\(UUID().uuidString)","name":"Legacy"}
        """
        let legacyContact = try JSONDecoder().decode(Contact.self, from: Data(legacyContactJSON.utf8))
        precondition(legacyContact.aliases.isEmpty)

        let contactID = try await store.addContact(name: "Ronald")
        try store.importNotes(text: "Met Ron today.", date: today, expectedSections: nil)
        precondition(store.data.notes.last?.contactIDs.isEmpty == true)
        try await store.updateContact(id: contactID, name: "Ronald", aliasesCSV: "Ron, Ronnie", organisationID: nil)
        precondition(store.data.notes.last?.contactIDs.contains(contactID) == true)
        try store.addTask(text: "Call Ronnie")
        precondition(store.tasks(forContact: contactID).contains { $0.text == "Call Ronnie" })
        precondition(WIPStore(fileURL: fileURL).data.contacts.first { $0.id == contactID }?.aliases == ["Ron", "Ronnie"])

        let otherID = try await store.addContact(name: "Other")
        do {
            try await store.updateContact(id: otherID, name: "Other", aliasesCSV: "Ron", organisationID: nil)
            fatalError("Duplicate contact alias was accepted")
        } catch WIPError.duplicateName { }

        print("Date entry, exact duplicate, task ordering, and contact alias checks passed")
    }
}
