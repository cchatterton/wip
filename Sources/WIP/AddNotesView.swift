import SwiftUI
import UniformTypeIdentifiers

struct AddNotesView: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    let onSaved: (String) -> Void

    @State private var text = ""
    @State private var dateText = NoteDateInput.todayText()
    @State private var showImporter = false
    @State private var showJSONImporter = false
    @FocusState private var textFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 26)
                HStack {
                    Spacer()
                    Text("Add notes")
                        .font(.system(size: 38, weight: .semibold))
                    Spacer()
                }
                .padding(.bottom, 38)

                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .font(WIPStyle.bodyFont)
                            .scrollContentBackground(.hidden)
                            .padding(18)
                            .focused($textFocused)
                        if text.isEmpty {
                            Text("Paste your notes here…")
                                .font(WIPStyle.bodyFont)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 24)
                                .padding(.top, 25)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: min(520, max(300, geometry.size.height * 0.54)))

                    Rectangle().fill(WIPStyle.divider).frame(height: 1)

                    HStack(spacing: 18) {
                        HStack(spacing: 8) {
                            Text("Date")
                                .foregroundStyle(.secondary)
                            TextField("d/m/yy", text: $dateText)
                                .textFieldStyle(.plain)
                                .frame(width: 98, height: 28)
                                .padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: 6).stroke(WIPStyle.divider))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .font(.system(size: 13))

                        Spacer()
                        Button { showImporter = true } label: {
                            Text("Open text file…")
                                .frame(minHeight: 30)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                        HStack(spacing: 8) {
                            Button { showJSONImporter = true } label: {
                                Text("Import JSON").frame(width: 100).contentShape(Rectangle())
                            }
                            Button(action: save) {
                                Text("Save notes").frame(width: 100).contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(WIPStyle.raisedSurface(colorScheme)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WIPStyle.divider))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 26)
            }
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                text = try String(contentsOf: url, encoding: .utf8)
                textFocused = true
            } catch {
                store.report(error)
            }
        }
        .fileImporter(isPresented: $showJSONImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let result = try store.importNoteArchive(Data(contentsOf: url))
                if result.added > 0 || result.skipped > 0 { onSaved(result.search) }
                store.errorMessage = "Imported \(result.added) \(result.added == 1 ? "note" : "notes")." +
                    (result.skipped > 0 ? " Skipped \(result.skipped) duplicates." : "")
            } catch {
                store.report(error)
            }
        }
    }

    private func save() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.report(WIPError.emptyText)
            return
        }
        do {
            let date = try NoteDateInput.parse(dateText)
            let skipped = try store.importNotes(text: text, date: date, expectedSections: nil)
            text = ""
            onSaved(NoteDateInput.text(for: date))
            if skipped > 0 {
                store.errorMessage = "Saved the new notes and skipped \(skipped) duplicate \(skipped == 1 ? "note" : "notes")."
            }
        } catch {
            store.report(error)
        }
    }
}
