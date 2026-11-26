import SwiftUI
import UniformTypeIdentifiers

struct TasksSidebar: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    let organisationID: UUID?
    let contactID: UUID?
    @State private var newTask = ""
    @State private var draggingID: UUID?
    @State private var editing: TaskItem?
    @FocusState private var newTaskFocused: Bool

    private var visibleTasks: [TaskItem] {
        if let organisationID { return store.tasks(forOrganisation: organisationID) }
        if let contactID { return store.tasks(forContact: contactID) }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasks")
                .font(.system(size: 22, weight: .semibold))
                .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(TaskLane.allCases, id: \.self) { lane in
                        laneSection(lane)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 0) {
                TextField("New task", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($newTaskFocused)
                    .onSubmit(addTask)
                    .padding(.leading, 10)
                    .disabled(organisationID == nil && contactID == nil)
                Rectangle().fill(WIPStyle.divider).frame(width: 1, height: 34)
                Button(action: addTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(organisationID == nil && contactID == nil)
                .accessibilityLabel("Add task")
            }
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(WIPStyle.raisedSurface(colorScheme)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WIPStyle.divider))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                if organisationID != nil || contactID != nil { newTaskFocused = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 26)
        .sheet(item: $editing) { task in TaskEditorSheet(task: task) }
    }

    private func laneSection(_ lane: TaskLane) -> some View {
        let tasks = visibleTasks.filter { $0.lane == lane }
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(WIPStyle.divider).frame(height: 1)
                .padding(.bottom, 15)
            Text(lane.rawValue)
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 11)
            ForEach(tasks) { task in
                taskRow(task)
            }
            if tasks.isEmpty {
                Text("Drop tasks here")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { _ in
            guard let draggingID else { return false }
            store.moveTask(draggingID, to: lane)
            self.draggingID = nil
            return true
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { task.completedAt != nil },
                set: { _ in store.toggleTask(task.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .padding(.top, 2)
            Text(task.text)
                .font(WIPStyle.bodyFont)
                .foregroundStyle(task.completedAt == nil ? Color.primary : Color.secondary)
                .strikethrough(task.completedAt != nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Edit") { editing = task }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 7)
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

    private func addTask() {
        do {
            try store.addTask(text: newTask, organisationID: organisationID, contactID: contactID)
            newTask = ""
        } catch {
            store.report(error)
        }
    }
}

struct TaskEditorSheet: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var text: String
    @State private var errorMessage: String?

    init(task: TaskItem) {
        self.task = task
        _text = State(initialValue: task.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit task").font(.system(size: 23, weight: .semibold))
            TextField("Task", text: $text).softField()
            if let errorMessage {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    do {
                        try store.updateTask(task.id, text: text)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 440)
        .onChange(of: text) { _ in errorMessage = nil }
    }
}
