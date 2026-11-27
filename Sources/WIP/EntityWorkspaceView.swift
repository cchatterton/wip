import AppKit
import SwiftUI

enum EntityKind: Equatable {
    case organisation
    case contact
}

struct EntityFocus: Equatable {
    let kind: EntityKind
    let id: UUID
    let name: String
}

struct EntityWorkspaceView: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("highlightHex") private var highlightHex = WIPStyle.defaultHighlightHex
    let kind: EntityKind
    let focus: EntityFocus?
    let onNavigate: (EntityFocus) -> Void
    let onCopy: () -> Void
    @State private var query = ""
    @State private var feedQuery = ""
    @State private var newName = ""
    @State private var selectedID: UUID?
    @State private var editingOrganisation: Organisation?
    @State private var editingContact: Contact?
    @State private var editingNote: Note?
    @State private var displayedNoteCount = 10
    @State private var showCopiedAlert = false
    @FocusState private var sidebarSearchFocused: Bool
    @FocusState private var feedSearchFocused: Bool
    @FocusState private var newNameFocused: Bool

    private var selectedOrganisation: Organisation? {
        store.data.organisations.first { $0.id == selectedID }
    }
    private var selectedContact: Contact? {
        store.data.contacts.first { $0.id == selectedID }
    }

    private var selectedFeedNotes: [Note] {
        if kind == .organisation, let selectedID {
            return store.data.notes.filter { $0.organisationID == selectedID }
        }
        if kind == .contact, let selectedID {
            return store.data.notes.filter { $0.contactIDs.contains(selectedID) }
        }
        return []
    }

    private var visibleFeedNotes: [Note] {
        Array(orderedNotes(filteredFeedNotes).prefix(displayedNoteCount))
    }

    private var filteredFeedNotes: [Note] {
        let term = feedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return selectedFeedNotes }
        return selectedFeedNotes.filter { $0.body.localizedCaseInsensitiveContains(term) }
    }

    private var filteredOrganisations: [Organisation] {
        store.data.organisations.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var filteredContacts: [Contact] {
        store.data.contacts.filter { contact in
            query.isEmpty || contact.matchTerms.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: WIPStyle.sidebarWidth)
                .background(WIPStyle.sidebarSurface(colorScheme))
            Rectangle().fill(WIPStyle.divider).frame(width: 1)
            details
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WIPStyle.readingSurface(colorScheme))
            Rectangle().fill(WIPStyle.divider).frame(width: 1)
            TasksSidebar(organisationID: kind == .organisation ? selectedID : nil,
                         contactID: kind == .contact ? selectedID : nil)
                .frame(width: WIPStyle.sidebarWidth)
                .background(WIPStyle.sidebarSurface(colorScheme))
        }
        .onAppear(perform: applyFocus)
        .onChange(of: focus) { _ in applyFocus() }
        .onChange(of: selectedID) { _ in
            displayedNoteCount = 10
            feedQuery = ""
        }
        .onChange(of: feedQuery) { _ in displayedNoteCount = 10 }
        .onChange(of: store.data.organisations) { _ in ensureSelection() }
        .onChange(of: store.data.contacts) { _ in ensureSelection() }
        .sheet(item: $editingOrganisation) { OrganisationEditorSheet(organisation: $0) }
        .sheet(item: $editingContact) { ContactEditorSheet(contact: $0) }
        .sheet(item: $editingNote) { NoteEditorSheet(note: $0) }
        .alert("Feed copied to clipboard.", isPresented: $showCopiedAlert) {
            Button("OK") { }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(kind == .organisation ? "Organisations" : "Contacts")
                    .font(.system(size: 22, weight: .semibold))
                Text("\(kind == .organisation ? filteredOrganisations.count : filteredContacts.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(WIPStyle.highlightSurface(colorScheme, hex: highlightHex)))
            }
            .padding(.bottom, 22)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(kind == .organisation ? "Filter organisations…" : "Filter contacts…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($sidebarSearchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 35)
            .background(RoundedRectangle(cornerRadius: 8).fill(WIPStyle.raisedSurface(colorScheme)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WIPStyle.divider))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { sidebarSearchFocused = true }
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if kind == .organisation {
                        ForEach(filteredOrganisations) { organisation in
                            entityRow(id: organisation.id, name: organisation.name)
                        }
                    } else {
                        ForEach(filteredContacts) { contact in
                            entityRow(id: contact.id, name: contact.name)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 0) {
                TextField(kind == .organisation ? "New organisation" : "New contact", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($newNameFocused)
                    .onSubmit(addEntity)
                    .padding(.leading, 10)
                Rectangle().fill(WIPStyle.divider).frame(width: 1, height: 34)
                Button(action: addEntity) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind == .organisation ? "Add organisation" : "Add contact")
            }
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(WIPStyle.raisedSurface(colorScheme)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WIPStyle.divider))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { newNameFocused = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 26)
    }

    private func entityRow(id: UUID, name: String) -> some View {
        Button {
            selectedID = id
        } label: {
            Text(name)
                .font(WIPStyle.bodyFont)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(selectedID == id ? WIPStyle.selected : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var details: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter notes…", text: $feedQuery)
                    .textFieldStyle(.plain)
                    .font(WIPStyle.bodyFont)
                    .focused($feedSearchFocused)
                if !feedQuery.isEmpty {
                    Button { feedQuery = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear note filter")
                }
            }
            .padding(.horizontal, 35)
            .frame(height: 78)
            .frame(maxWidth: .infinity)
            .background(WIPStyle.sidebarSurface(colorScheme))
            .contentShape(Rectangle())
            .onTapGesture { feedSearchFocused = true }

            Rectangle().fill(WIPStyle.divider).frame(height: 1)

            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if kind == .organisation, let organisation = selectedOrganisation {
                    titleRow(organisation.name) { editingOrganisation = organisation }
                    VStack(alignment: .leading, spacing: 2) {
                        if !organisation.aliases.isEmpty {
                            metadata(label: "Aliases", value: organisation.aliases.joined(separator: ", "))
                        }
                        let contacts = relatedContacts(for: organisation)
                        if !contacts.isEmpty {
                            relatedContactsMetadata(contacts)
                        }
                    }
                    .padding(.bottom, 28)
                    noteFeed(for: filteredFeedNotes, highlightContacts: true)
                } else if kind == .contact, let contact = selectedContact {
                    titleRow(contact.name) { editingContact = contact }
                    VStack(alignment: .leading, spacing: 2) {
                        if !contact.aliases.isEmpty {
                            metadata(label: "Aliases", value: contact.aliases.joined(separator: ", "))
                        }
                        if let organisationID = contact.organisationID,
                           let organisation = store.data.organisations.first(where: { $0.id == organisationID }) {
                            linkedOrganisationMetadata(organisation)
                        }
                        let related = relatedOrganisations(for: contact)
                        if !related.isEmpty {
                            relatedOrganisationsMetadata(related)
                        }
                    }
                    .padding(.bottom, 28)
                    noteFeed(for: filteredFeedNotes,
                             showOrganisationHeading: true, highlightedContactTerms: contact.matchTerms)
                }
            }
            .frame(maxWidth: WIPStyle.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 50)
        }
        .scrollIndicators(.hidden)
        }
    }

    private func titleRow(_ name: String, edit: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(name)
                .font(.system(size: 25, weight: .semibold))
                .lineLimit(3)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Export", action: copyVisibleFeed)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(visibleFeedNotes.isEmpty)
                Button("Edit", action: edit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.bottom, 7)
    }

    private func metadata(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            copyMetadataLabel(label, value: value)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(size: 14))
        .lineSpacing(1)
    }

    private func relatedContactsMetadata(_ contacts: [Contact]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            copyMetadataLabel("Related", value: contacts.map(\.name).joined(separator: ", "))
            Text(contactLinks(contacts))
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "wip", url.host == "contact",
                          let id = UUID(uuidString: url.lastPathComponent),
                          let contact = store.data.contacts.first(where: { $0.id == id }) else {
                        return .discarded
                    }
                    onNavigate(EntityFocus(kind: .contact, id: contact.id, name: contact.name))
                    return .handled
                })
        }
        .font(.system(size: 14))
        .lineSpacing(1)
    }

    private func contactLinks(_ contacts: [Contact]) -> AttributedString {
        var result = AttributedString()
        for (index, contact) in contacts.enumerated() {
            if index > 0 { result += AttributedString(", ") }
            var name = AttributedString(contact.name)
            name.link = URL(string: "wip://contact/\(contact.id.uuidString)")
            name.foregroundColor = Color.primary
            result += name
        }
        return result
    }

    private func linkedOrganisationMetadata(_ organisation: Organisation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            copyMetadataLabel("Organisation", value: organisation.name)
            Button {
                onNavigate(EntityFocus(kind: .organisation, id: organisation.id, name: organisation.name))
            } label: {
                Text(organisation.name)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14))
        .lineSpacing(1)
    }

    private func relatedOrganisationsMetadata(_ organisations: [Organisation]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            copyMetadataLabel("Related", value: organisations.map(\.name).joined(separator: ", "))
            Text(organisationLinks(organisations))
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "wip", url.host == "organisation",
                          let id = UUID(uuidString: url.lastPathComponent),
                          let organisation = store.data.organisations.first(where: { $0.id == id }) else {
                        return .discarded
                    }
                    onNavigate(EntityFocus(kind: .organisation, id: organisation.id, name: organisation.name))
                    return .handled
                })
        }
        .font(.system(size: 14))
        .lineSpacing(1)
    }

    private func organisationLinks(_ organisations: [Organisation]) -> AttributedString {
        var result = AttributedString()
        for (index, organisation) in organisations.enumerated() {
            if index > 0 { result += AttributedString(", ") }
            var name = AttributedString(organisation.name)
            name.link = URL(string: "wip://organisation/\(organisation.id.uuidString)")
            name.foregroundColor = Color.primary
            result += name
        }
        return result
    }

    private func copyMetadataLabel(_ label: String, value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(value, forType: .string) {
                onCopy()
            } else {
                store.errorMessage = "Could not copy \(label.lowercased()) to the clipboard."
            }
        } label: {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy \(label.lowercased())")
        .accessibilityLabel("Copy \(label)")
    }

    private func applyFocus() {
        if let focus, focus.kind == kind {
            selectedID = focus.id
            query = focus.name
        } else {
            selectedID = nil
            query = ""
        }
        ensureSelection()
    }

    private func relatedContacts(for organisation: Organisation) -> [Contact] {
        let mentionedIDs = Set(store.data.notes
            .filter { $0.organisationID == organisation.id }
            .flatMap(\.contactIDs))
        return store.data.contacts.filter {
            $0.organisationID == organisation.id || mentionedIDs.contains($0.id)
        }
    }

    private func relatedOrganisations(for contact: Contact) -> [Organisation] {
        let ids = Set(store.data.notes.compactMap { note -> UUID? in
            guard note.contactIDs.contains(contact.id),
                  let organisationID = note.organisationID,
                  organisationID != contact.organisationID else { return nil }
            return organisationID
        })
        return store.data.organisations.filter { ids.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func orderedNotes(_ notes: [Note]) -> [Note] {
        notes.sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return $0.date > $1.date
        }
    }

    private func copyVisibleFeed() {
        guard !visibleFeedNotes.isEmpty else { return }
        let title = kind == .organisation ? selectedOrganisation?.name : selectedContact?.name
        let entries = visibleFeedNotes.map { note in
            var parts: [String] = []
            if kind == .contact,
               let organisation = store.data.organisations.first(where: { $0.id == note.organisationID }) {
                parts.append(organisation.name)
            }
            parts.append(note.date.formatted(date: .abbreviated, time: .omitted))
            parts.append(note.body)
            return parts.joined(separator: "\n")
        }
        let text = ([title].compactMap { $0 } + entries).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) {
            onCopy()
            showCopiedAlert = true
        } else {
            store.errorMessage = "Could not copy the feed to the clipboard."
        }
    }

    private func noteFeed(for notes: [Note], showOrganisationHeading: Bool = false,
                          highlightContacts: Bool = false,
                          highlightedContactTerms: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let sorted = orderedNotes(notes)
            if sorted.isEmpty {
                Text(feedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "No notes yet" : "No matching notes")
                    .font(WIPStyle.bodyFont)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sorted.prefix(displayedNoteCount))) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                if showOrganisationHeading,
                                   let organisation = store.data.organisations.first(where: { $0.id == note.organisationID }) {
                                    Text(organisation.name)
                                        .font(WIPStyle.bodyFont)
                                        .fontWeight(.medium)
                                }
                                Text(note.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("Edit") { editingNote = note }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        NoteTextView(
                            text: note.body,
                            searchQuery: feedQuery,
                            contactNames: !highlightedContactTerms.isEmpty
                                ? highlightedContactTerms
                                : (highlightContacts
                                    ? store.data.contacts.filter { note.contactIDs.contains($0.id) }.flatMap(\.matchTerms)
                                    : [])
                        )
                    }
                    .padding(.vertical, 18)
                    Rectangle().fill(WIPStyle.divider).frame(height: 1)
                }
                if displayedNoteCount < sorted.count {
                    Color.clear.frame(height: 1)
                        .onAppear { displayedNoteCount += 10 }
                }
                }
            }
        }
    }

    private func ensureSelection() {
        guard let selectedID else { return }
        if kind == .organisation {
            if !store.data.organisations.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } else {
            if !store.data.contacts.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
    }

    private func addEntity() {
        Task {
            do {
                if kind == .organisation {
                    selectedID = try await store.addOrganisation(name: newName)
                } else {
                    selectedID = try await store.addContact(name: newName)
                }
                newName = ""
            } catch {
                store.report(error)
            }
        }
    }
}

struct OrganisationEditorSheet: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.dismiss) private var dismiss
    let organisation: Organisation
    @State private var name: String
    @State private var aliases: String
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(organisation: Organisation) {
        self.organisation = organisation
        _name = State(initialValue: organisation.name)
        _aliases = State(initialValue: organisation.aliases.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit organisation").font(.system(size: 23, weight: .semibold))
            VStack(alignment: .leading, spacing: 7) {
                Text("Name").font(.system(size: 13))
                TextField("Name", text: $name).softField()
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Aliases").font(.system(size: 13))
                TextField("Aliases", text: $aliases).softField()
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
            }
            HStack {
                Button("Delete organisation", role: .destructive) { confirmDelete = true }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    Task {
                        do {
                            try await store.updateOrganisation(id: organisation.id, name: name, aliasesCSV: aliases)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(26)
        .frame(width: 440)
        .overlay {
            if let message = store.processingMessage { ProcessingOverlay(message: message) }
        }
        .onChange(of: name) { _ in errorMessage = nil }
        .onChange(of: aliases) { _ in errorMessage = nil }
        .confirmationDialog("Delete \(organisation.name)?", isPresented: $confirmDelete) {
            Button("Delete organisation", role: .destructive) {
                Task {
                    await store.deleteOrganisation(id: organisation.id)
                    dismiss()
                }
            }
        }
    }
}

struct ContactEditorSheet: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.dismiss) private var dismiss
    let contact: Contact
    @State private var name: String
    @State private var aliases: String
    @State private var organisationID: UUID?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(contact: Contact) {
        self.contact = contact
        _name = State(initialValue: contact.name)
        _aliases = State(initialValue: contact.aliases.joined(separator: ", "))
        _organisationID = State(initialValue: contact.organisationID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit contact").font(.system(size: 23, weight: .semibold))
            VStack(alignment: .leading, spacing: 7) {
                Text("Name").font(.system(size: 13))
                TextField("Name", text: $name).softField()
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Aliases").font(.system(size: 13))
                TextField("Aliases", text: $aliases).softField()
            }
            OrganisationSearchPicker(selection: $organisationID)
            if let errorMessage {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
            }
            HStack {
                Button("Delete contact", role: .destructive) { confirmDelete = true }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    Task {
                        do {
                            try await store.updateContact(id: contact.id, name: name, aliasesCSV: aliases,
                                                          organisationID: organisationID)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(26)
        .frame(width: 440)
        .overlay {
            if let message = store.processingMessage { ProcessingOverlay(message: message) }
        }
        .onChange(of: name) { _ in errorMessage = nil }
        .onChange(of: aliases) { _ in errorMessage = nil }
        .confirmationDialog("Delete \(contact.name)?", isPresented: $confirmDelete) {
            Button("Delete contact", role: .destructive) {
                Task {
                    await store.deleteContact(id: contact.id)
                    dismiss()
                }
            }
        }
    }
}
