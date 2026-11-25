import AppKit
import Combine
import SwiftUI

@main
struct WIPApp: App {
    @NSApplicationDelegateAdaptor(WIPApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store = WIPStore()

    var body: some Scene {
        WindowGroup {
            WIPRootView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1480, height: 900)
    }
}

final class WIPApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "WIPIcon-1024", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}

enum WIPTab: String, CaseIterable {
    case addNotes = "Add notes"
    case notes = "Notes"
    case organisations = "Organisations"
    case contacts = "Contacts"
    case tasks = "Tasks"
}

enum WIPStyle {
    static let defaultHighlightHex = "#E26B2E"
    static let background = Color(nsColor: .windowBackgroundColor)
    static let divider = Color.primary.opacity(0.11)
    static let muted = Color.secondary
    static let selected = Color.primary.opacity(0.065)
    static let sidebarWidth: CGFloat = 330
    static let readingWidth: CGFloat = 680
    static let bodyFont = Font.system(size: 15)

    static func sidebarSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.185, green: 0.193, blue: 0.205)
            : Color(red: 0.985, green: 0.987, blue: 0.990)
    }

    static func readingSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.145, green: 0.153, blue: 0.165)
            : Color(red: 0.945, green: 0.949, blue: 0.955)
    }

    static func raisedSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.235, green: 0.244, blue: 0.258)
            : Color.white
    }

    static func normalizedHighlightHex(_ input: String) -> String? {
        let digits = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "").uppercased()
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + digits
    }

    static func highlightSurface(_ scheme: ColorScheme, hex: String) -> Color {
        let normalized = normalizedHighlightHex(hex) ?? defaultHighlightHex
        let value = UInt32(normalized.dropFirst(), radix: 16) ?? 0xE26B2E
        let base = Color(red: Double((value >> 16) & 0xFF) / 255,
                         green: Double((value >> 8) & 0xFF) / 255,
                         blue: Double(value & 0xFF) / 255)
        return base.opacity(scheme == .dark ? 0.68 : 0.35)
    }
}

struct WIPRootView: View {
    @EnvironmentObject private var store: WIPStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab: WIPTab = .addNotes
    @State private var entityFocus: EntityFocus?
    @State private var notesSearchRequest: NotesSearchRequest?
    @State private var showHighlightEditor = false
    @AppStorage("highlightHex") private var highlightHex = WIPStyle.defaultHighlightHex

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(WIPStyle.divider).frame(height: 1)
            Group {
                switch tab {
                case .addNotes:
                    AddNotesView { search in
                        notesSearchRequest = NotesSearchRequest(query: search)
                        tab = .notes
                    }
                case .notes:
                    NotesView(searchRequest: notesSearchRequest)
                case .organisations:
                    EntityWorkspaceView(kind: .organisation, focus: entityFocus, onNavigate: navigate)
                case .contacts:
                    EntityWorkspaceView(kind: .contact, focus: entityFocus, onNavigate: navigate)
                case .tasks:
                    TasksBoardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WIPStyle.background)
        .overlay {
            if let message = store.processingMessage {
                ProcessingOverlay(message: message)
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { store.now = $0 }
        .alert("WIP", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(isPresented: $showHighlightEditor) {
            HighlightColourSheet(highlightHex: $highlightHex)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                if let url = Bundle.main.url(forResource: "WIPMark", withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Button { showHighlightEditor = true } label: {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 20, height: 25)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit highlight colour")
                }
                Text("WIP")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.leading, 24)
            Spacer()
            HStack(spacing: 32) {
                ForEach(WIPTab.allCases, id: \.self) { item in
                    Button {
                        entityFocus = nil
                        if item == .notes { notesSearchRequest = nil }
                        tab = item
                    } label: {
                        VStack(spacing: 11) {
                            Text(item.rawValue)
                                .font(.system(size: 14, weight: tab == item ? .medium : .regular))
                            Rectangle()
                                .fill(tab == item ? Color.primary : Color.clear)
                                .frame(width: 28, height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.trailing, 24)
        }
        .frame(height: 64)
        .background(WIPStyle.sidebarSurface(colorScheme))
    }

    private func navigate(_ focus: EntityFocus) {
        entityFocus = focus
        tab = focus.kind == .organisation ? .organisations : .contacts
    }
}

struct ProcessingOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(WIPStyle.raisedSurface(colorScheme)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(WIPStyle.divider))
        }
    }
}

struct HighlightColourSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var highlightHex: String
    @State private var draft = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Highlight colour").font(.system(size: 23, weight: .semibold))
            HStack(spacing: 12) {
                TextField("#E26B2E", text: $draft)
                    .softField()
                    .onChange(of: draft) { _ in errorMessage = nil }
                RoundedRectangle(cornerRadius: 6)
                    .fill(WIPStyle.highlightSurface(colorScheme, hex: draft))
                    .frame(width: 38, height: 34)
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    guard let normalized = WIPStyle.normalizedHighlightHex(draft) else {
                        errorMessage = "Enter a six-digit hex colour, such as #E26B2E."
                        return
                    }
                    highlightHex = normalized
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 360)
        .onAppear { draft = highlightHex }
    }
}

struct SoftField: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(WIPStyle.raisedSurface(colorScheme)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WIPStyle.divider))
    }
}

extension View {
    func softField() -> some View { modifier(SoftField()) }
}

extension WIPStore {
    func report(_ error: Error) { errorMessage = error.localizedDescription }
}
