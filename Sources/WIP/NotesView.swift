import SwiftUI
import UniformTypeIdentifiers

struct NotesSearchRequest: Equatable {
    let id = UUID()
    let query: String
}

struct NotesView: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("highlightHex") private var highlightHex = WIPStyle.defaultHighlightHex
    @AppStorage("recentNoteSearches") private var recentSearchesJSON = "[]"
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var selected: Set<UUID> = []
    @State private var editing: Note?
    @State private var pendingDelete: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var exportDocument: NoteArchiveDocument?
    @State private var showExporter = false
    @State private var displayedCount = 10
    let searchRequest: NotesSearchRequest?

    init(searchRequest: NotesSearchRequest?) {
        self.searchRequest = searchRequest
        _query = State(initialValue: searchRequest?.query ?? "")
    }

    private var recentSearches: [String] {
        guard let data = recentSearchesJSON.data(using: .utf8),
              let searches = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(searches.prefix(10))
    }

    private var visibleNotes: [Note] {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchedDate = try? NoteDateInput.parse(searchText)
        return store.data.notes.filter { note in
            if let searchedDate {
                return Calendar.current.isDate(note.date, inSameDayAs: searchedDate)
            }
            return searchText.isEmpty ||
            note.body.localizedCaseInsensitiveContains(searchText) ||
            organisationName(for: note).localizedCaseInsensitiveContains(searchText)
        }.sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return $0.date > $1.date
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Notes")
                        .font(.system(size: 34, weight: .semibold))
                    Spacer()
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Export") { exportVisibleNotes() }
                            .buttonStyle(.bordered)
                            .disabled(visibleNotes.isEmpty)
                    }
                }
                .padding(.bottom, 24)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes or date…", text: $query)
                        .textFieldStyle(.plain)
                        .font(WIPStyle.bodyFont)
                        .focused($searchFocused)
                        .onSubmit { rememberSearch(query) }
                    if !query.isEmpty {
                        Button {
                            rememberSearch(query)
                            query = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 15)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(WIPStyle.raisedSurface(colorScheme)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WIPStyle.divider))
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { searchFocused = true }
                .onChange(of: query) { _ in
                    selected.removeAll()
                    displayedCount = 10
                }
                .onChange(of: searchFocused) { focused in
                    if !focused { rememberSearch(query) }
                }
                .padding(.bottom, recentSearches.isEmpty ? 17 : 10)

                if !recentSearches.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(recentSearches, id: \.self) { search in
                                Button {
                                    rememberSearch(query)
                                    query = search
                                    rememberSearch(search)
                                } label: {
                                    Text(search)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(WIPStyle.raisedSurface(colorScheme)))
                                        .overlay(Capsule().stroke(WIPStyle.divider))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.bottom, 17)
                }

                if !selected.isEmpty {
                    HStack {
                        Text("\(selected.count) selected")
                        Spacer()
                        Button("Merge") { merge() }
                            .disabled(selected.count < 2)
                        Button("Delete", role: .destructive) {
                            pendingDelete = selected
                            confirmDelete = true
                        }
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 15)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 9).fill(WIPStyle.raisedSurface(colorScheme)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(WIPStyle.divider))
                    .padding(.bottom, 12)
                }

                if visibleNotes.isEmpty {
                    VStack(spacing: 8) {
                        Text(query.isEmpty ? "No notes yet" : "No matching notes")
                            .font(.system(size: 18, weight: .medium))
                        Text(query.isEmpty ? "Add notes to see them here." : "Try another search.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleNotes.prefix(displayedCount))) { note in
                            noteRow(note)
                            Rectangle().fill(WIPStyle.divider).frame(height: 1)
                        }
                        if displayedCount < visibleNotes.count {
                            Color.clear.frame(height: 1)
                                .onAppear { displayedCount += 10 }
                        }
                    }
                }
            }
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 35)
            .padding(.top, 42)
            .padding(.bottom, 60)
        }
        .sheet(item: $editing) { note in NoteEditorSheet(note: note) }
        .onAppear { rememberSearch(query) }
        .onDisappear { rememberSearch(query) }
        .onChange(of: searchRequest) { _ in applySearchRequest() }
        .fileExporter(isPresented: $showExporter, document: exportDocument,
                      contentType: .json, defaultFilename: "WIP-notes") { result in
            if case .failure(let error) = result { store.report(error) }
            exportDocument = nil
        }
        .confirmationDialog("Delete selected notes?", isPresented: $confirmDelete) {
            Button("Delete \(pendingDelete.count) notes", role: .destructive) {
                store.deleteNotes(ids: pendingDelete)
                selected.subtract(pendingDelete)
                pendingDelete.removeAll()
            }
        } message: {
            Text("Deleted notes cannot be recovered from this view.")
        }
    }

    private func organisationName(for note: Note) -> String {
        store.data.organisations.first(where: { $0.id == note.organisationID })?.name ?? "Unassigned"
    }

    private func noteRow(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Toggle("", isOn: Binding(
                get: { selected.contains(note.id) },
                set: { checked in
                    if checked { selected.insert(note.id) } else { selected.remove(note.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                if note.organisationID != nil,
                   let organisation = store.data.organisations.first(where: { $0.id == note.organisationID }) {
                    Text(highlightedSearch(organisation.name))
                        .font(.system(size: 16, weight: .medium))
                }
                Text(note.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text(highlightedSearch(note.body))
                    .font(WIPStyle.bodyFont)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
            }
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                Button("Edit") { editing = note }
                Button("Delete") {
                    pendingDelete = [note.id]
                    confirmDelete = true
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .padding(.top, 7)
        }
        .padding(.vertical, 20)
    }

    private func merge() {
        do {
            try store.mergeNotes(ids: selected)
            selected.removeAll()
        } catch {
            store.report(error)
        }
    }

    private func exportVisibleNotes() {
        do {
            let archive = NoteArchive(notes: visibleNotes, organisations: store.data.organisations,
                                      search: query.trimmingCharacters(in: .whitespacesAndNewlines))
            exportDocument = NoteArchiveDocument(data: try archive.encoded())
            showExporter = true
        } catch {
            store.report(error)
        }
    }

    private func applySearchRequest() {
        guard let searchRequest else { return }
        query = searchRequest.query
        displayedCount = 10
        rememberSearch(query)
    }

    private func rememberSearch(_ value: String) {
        let search = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return }
        var updated = recentSearches.filter { $0.caseInsensitiveCompare(search) != .orderedSame }
        updated.insert(search, at: 0)
        if let data = try? JSONEncoder().encode(Array(updated.prefix(10))),
           let encoded = String(data: data, encoding: .utf8), encoded != recentSearchesJSON {
            recentSearchesJSON = encoded
        }
    }

    private func highlightedSearch(_ value: String) -> AttributedString {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? NoteDateInput.parse(searchText)) == nil else {
            return AttributedString(value)
        }
        return SearchHighlight.text(value, query: searchText, colorScheme: colorScheme, highlightHex: highlightHex)
    }
}

struct NoteEditorSheet: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var noteText: String
    @State private var date: Date
    @State private var organisationID: UUID?
    @State private var errorMessage: String?

    init(note: Note) {
        self.note = note
        _noteText = State(initialValue: note.body)
        _date = State(initialValue: note.date)
        _organisationID = State(initialValue: note.organisationID)
    }

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit note").font(.system(size: 24, weight: .semibold))
            HStack {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Picker("Organisation", selection: $organisationID) {
                    Text("Unassigned").tag(nil as UUID?)
                    ForEach(store.data.organisations) { organisation in
                        Text(organisation.name).tag(Optional(organisation.id))
                    }
                }
            }
            TextEditor(text: $noteText)
                .font(WIPStyle.bodyFont)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WIPStyle.divider))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 230)
            if let errorMessage {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    do {
                        try store.updateNote(id: note.id, date: date, body: noteText, organisationID: organisationID)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 620)
        .frame(minHeight: 400)
        .onChange(of: noteText) { _ in errorMessage = nil }
        .onChange(of: date) { _ in errorMessage = nil }
        .onChange(of: organisationID) { _ in errorMessage = nil }
    }

    var body: some View { bodyView }
}
