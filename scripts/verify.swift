import Foundation

enum VerificationError: Error {
    case failed(String)
}

@main
struct Verify {
    @MainActor
    static func main() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WIPVerify-\(UUID().uuidString)")
            .appendingPathComponent("WIP.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = WIPStore(fileURL: fileURL)
        let source = """
        Mission Aviation Fellowship
        Spoke with Sarah Chen about the field plan.

        North Harbour Group
        Discussed the follow-up.
        """
        try store.importNotes(text: source, date: Date(), expectedSections: 2)
        try check(store.data.notes.count == 1, "Unmatched headings remain in one note")

        let missionID = try await store.addOrganisation(name: "Mission Aviation Fellowship")
        try check(store.data.notes.count == 1, "First organisation is recognised")
        let northID = try await store.addOrganisation(name: "North Harbour Group")
        try check(store.data.notes.count == 2, "New organisation splits historical note")
        try check(Set(store.data.notes.compactMap(\.organisationID)) == Set([missionID, northID]),
                  "Both sections are correctly tagged")

        let sarahID = try await store.addContact(name: "Sarah Chen")
        try check(store.data.notes.filter { $0.contactIDs.contains(sarahID) }.count == 1,
                  "New contact retags historical note")
        try await store.updateOrganisation(id: missionID, name: "Mission Aviation Fellowship", aliasesCSV: "MAF, MAF AU")
        try store.addTask(text: "Review MAF field plan with Sarah Chen", contactID: sarahID)
        let contactTask = try require(store.tasks(forContact: sarahID).first, "Task appears on contact")
        let organisationTask = try require(store.tasks(forOrganisation: missionID).first, "Task appears on organisation")
        try check(contactTask.id == organisationTask.id, "Task is shared, not duplicated")
        store.moveTask(contactTask.id, to: .next)
        try check(store.tasks(forOrganisation: missionID).first?.lane == .next, "Task lane is shared")
        store.toggleTask(contactTask.id)
        try check(store.tasks(forOrganisation: missionID).first?.completedAt != nil, "Completion is shared")

        try store.addTask(text: "Ask Sarah Chen to confirm the schedule", organisationID: missionID)
        try check(store.tasks(forContact: sarahID).contains(where: { $0.text == "Ask Sarah Chen to confirm the schedule" }),
                  "Organisation task mentioning a contact appears on the contact")

        let reopened = WIPStore(fileURL: fileURL)
        try check(reopened.data.notes.count == 2 && reopened.data.imports.first?.rawText == source,
                  "Notes and original text persist")
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        var done = TaskItem(text: "Done")
        done.completedAt = start.addingTimeInterval(60)
        try check(done.isVisible(on: start.addingTimeInterval(3600), calendar: calendar), "Completed task stays visible today")
        try check(!done.isVisible(on: start.addingTimeInterval(86400), calendar: calendar), "Completed task hides after midnight")
        print("WIP verification passed")
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw VerificationError.failed(message) }
    }

    static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw VerificationError.failed(message) }
        return value
    }
}
