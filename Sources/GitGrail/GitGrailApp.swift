import AppKit
import SwiftUI

@main
struct GitGrailApp: App {
    @ViewState private var model = AppModel()

    init() {
        // Needed when the binary runs outside an app bundle, for example from `swift run`.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Git Grail") {
            ContentView().environment(model)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Project…") { addProjectPanel(model) }.keyboardShortcut("o")
            }
            CommandMenu("Git") {
                Button("Refresh") { Task { await model.refreshSelected() } }.keyboardShortcut("r")
                Button("Sync All Now") { Task { await model.syncAll() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor func addProjectPanel(_ model: AppModel) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Select a git repo"
    if panel.runModal() == .OK, let url = panel.url { Task { await model.addProject(at: url.path) } }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var showLog = false
    @ViewState private var showClone = false
    @ViewState private var newWorktreeFor: String?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(newWorktreeFor: $newWorktreeFor)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            switch model.selection {
            case .project(let path): ProjectView(path: path, newWorktreeFor: $newWorktreeFor)
            case .worktree(let wt): WorktreeView(wt: wt).id(wt)
            case nil: ContentUnavailableView("Select a project or worktree", systemImage: "arrow.triangle.branch")
            }
        }
        .inspector(isPresented: $showLog) { LogView().inspectorColumnWidth(min: 260, ideal: 340) }
        .toolbar {
            ToolbarItemGroup {
                if model.busy || model.syncing { ProgressView().controlSize(.small) }
                Button { Task { await model.syncAll() } } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    .help(model.lastSync.map { "Last sync: \($0.formatted(date: .omitted, time: .standard))" } ?? "Sync")
                Menu {
                    Button("Add Existing Repo…") { addProjectPanel(model) }
                    Button("Clone with gh…") { showClone = true }
                } label: { Label("Add Project", systemImage: "plus") }
                Button { showLog.toggle() } label: { Label("Action Log", systemImage: "list.bullet.rectangle") }
            }
        }
        .sheet(isPresented: $showClone) { CloneSheet() }
        .sheet(item: $newWorktreeFor) { NewWorktreeSheet(project: $0) }
        .alert("Git Grail", isPresented: Binding { model.alert != nil } set: { if !$0 { model.alert = nil } }) {
            Button("OK") {}
        } message: { Text(model.alert ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshSelected() }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// The SDK of the Command Line Tools declares `@State` as a macro without its plugin.
// This alias picks the property wrapper, so the app builds without Xcode.
typealias ViewState = SwiftUI.State
