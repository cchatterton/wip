import SwiftUI

struct OrganisationSearchPicker: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: UUID?
    @State private var isOpen = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var selectedName: String {
        store.data.organisations.first(where: { $0.id == selection })?.name ?? "None"
    }

    private var choices: [Organisation] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return store.data.organisations }
        return store.data.organisations.filter { organisation in
            ([organisation.name] + organisation.aliases)
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Organisation")
                .font(.system(size: 13))
            Button {
                query = ""
                isOpen = true
            } label: {
                HStack(spacing: 8) {
                    Text(selectedName)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7).fill(WIPStyle.raisedSurface(colorScheme)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(WIPStyle.divider))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose organisation, \(selectedName)")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search organisations…", text: $query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 7).fill(WIPStyle.raisedSurface(colorScheme)))

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            choiceRow(name: "None", id: nil)
                            ForEach(choices) { organisation in
                                choiceRow(name: organisation.name, id: organisation.id)
                            }
                            if choices.isEmpty {
                                Text("No matching organisations")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
                .padding(12)
                .frame(width: 320)
                .onAppear { searchFocused = true }
            }
        }
    }

    private func choiceRow(name: String, id: UUID?) -> some View {
        Button {
            selection = id
            isOpen = false
        } label: {
            HStack {
                Text(name).lineLimit(1)
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(selection == id ? WIPStyle.selected : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
