import SwiftUI
import UniformTypeIdentifiers

struct TasksBoardView: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("highlightHex") private var highlightHex = WIPStyle.defaultHighlightHex
    @State private var newTaskByLane: [TaskLane: String] = [:]
    @State private var draggingID: UUID?
    @State private var editing: TaskItem?
    @State private var query = ""

    private var searchText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter tasks…", text: $query)
                    .textFieldStyle(.plain)
                    .font(WIPStyle.bodyFont)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 35)
            .frame(height: 78)
            .frame(maxWidth: .infinity)
            .background(WIPStyle.readingSurface(colorScheme))

            Rectangle().fill(WIPStyle.divider).frame(height: 1)

            HStack(spacing: 0) {
                ForEach(TaskLane.allCases, id: \.self) { lane in
                    laneColumn(lane)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if lane != .later {
                        Rectangle().fill(WIPStyle.divider).frame(width: 1)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editing) { task in TaskEditorSheet(task: task) }
    }

    private func laneColumn(_ lane: TaskLane) -> some View {
        let tasks = store.data.tasks
            .filter { $0.lane == lane && $0.isVisible(on: store.now) && matchesSearch($0) }
            .sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }

        return VStack(alignment: .leading, spacing: 0) {
            Text(lane.rawValue)
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)

            Rectangle().fill(WIPStyle.divider).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        taskCard(task)
                    }
                    if tasks.isEmpty {
                        Text(searchText.isEmpty ? "Drop tasks here" : "No matching tasks")
                            .font(WIPStyle.bodyFont)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 130)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            addTaskField(for: lane)
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WIPStyle.sidebarSurface(colorScheme))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { _ in
            guard let draggingID else { return false }
            store.moveTask(draggingID, to: lane)
            self.draggingID = nil
            return true
        }
    }

    private func taskCard(_ task: TaskItem) -> some View {
        let organisations = connectedOrganisations(to: task)
        let contacts = connectedContacts(to: task)
        let connections = [
            organisations.isEmpty ? nil : "Organisation · " + organisations.joined(separator: ", "),
            contacts.isEmpty ? nil : "Contact · " + contacts.joined(separator: ", ")
        ].compactMap { $0 }.joined(separator: "   ·   ")
        let detail = connections.isEmpty ? "Unlinked" : connections

        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { task.completedAt != nil },
                set: { _ in store.toggleTask(task.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(SearchHighlight.text(task.text, query: searchText, colorScheme: colorScheme, highlightHex: highlightHex))
                    .font(WIPStyle.bodyFont)
                    .foregroundStyle(task.completedAt == nil ? Color.primary : Color.secondary)
                    .strikethrough(task.completedAt != nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(SearchHighlight.text(detail, query: searchText, colorScheme: colorScheme, highlightHex: highlightHex))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Button("Edit") { editing = task }
                Button("Delete") { store.deleteTask(task.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(WIPStyle.raisedSurface(colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WIPStyle.divider))
        .contentShape(Rectangle())
        .onDrag {
            draggingID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { _ in
            guard let draggingID, draggingID != task.id else { return false }
            store.moveTask(draggingID, to: task.lane, before: task.id)
            self.draggingID = nil
            return true
        }
        .contextMenu {
            Button("Edit") { editing = task }
            Button("Delete", role: .destructive) { store.deleteTask(task.id) }
        }
        .help("Drag to reorder or move task. Right-click to edit or delete.")
    }

    private func addTaskField(for lane: TaskLane) -> some View {
        HStack(spacing: 0) {
            TextField("New task", text: Binding(
                get: { newTaskByLane[lane, default: ""] },
                set: { newTaskByLane[lane] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .onSubmit { addTask(to: lane) }
            .padding(.leading, 10)

            Rectangle().fill(WIPStyle.divider).frame(width: 1, height: 34)
            Button { addTask(to: lane) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task to \(lane.rawValue)")
        }
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(WIPStyle.raisedSurface(colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WIPStyle.divider))
    }

    private func addTask(to lane: TaskLane) {
        do {
            try store.addTask(text: newTaskByLane[lane, default: ""], lane: lane)
            newTaskByLane[lane] = ""
        } catch {
            store.report(error)
        }
    }

    private func connectedOrganisations(to task: TaskItem) -> [String] {
        let mentioned = NoteParser.organisationIDs(in: task.text, from: store.data.organisations)
        return store.data.organisations
            .filter { $0.id == task.originOrganisationID || mentioned.contains($0.id) }
            .map(\.name)
    }

    private func connectedContacts(to task: TaskItem) -> [String] {
        store.data.contacts
            .filter { $0.id == task.originContactID || NoteParser.contains($0, in: task.text) }
            .map(\.name)
    }

    private func matchesSearch(_ task: TaskItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        let labels = connectedOrganisations(to: task) + connectedContacts(to: task)
        return task.text.localizedCaseInsensitiveContains(searchText) ||
            labels.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
            (labels.isEmpty && "Unlinked".localizedCaseInsensitiveContains(searchText))
    }
}
