import GrailCore
import SwiftUI

struct StatusIcon: View {
    let state: SyncState

    var body: some View {
        switch state {
        case .upToDate: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Up to date with main")
        case .behind: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).help("Behind main")
        case .conflict: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help("Rebase on main has conflicts")
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Status not known")
        }
    }
}

/// Shows "↑2 ↓5" for commits ahead of and behind main.
struct AheadBehind: View {
    let status: WorktreeStatus?

    var body: some View {
        if let s = status, s.ahead + s.behind > 0 {
            Text("\(s.ahead > 0 ? "↑\(s.ahead)" : "") \(s.behind > 0 ? "↓\(s.behind)" : "")")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var newWorktreeFor: String?
    @ViewState private var collapsed: Set<String> = []

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.projects) { p in
                DisclosureGroup(isExpanded: expanded(p.path)) {
                    ForEach(p.worktrees) { wt in row(p, wt).tag(Selection.worktree(wt.path)) }
                } label: {
                    Label { Text(p.name).fontWeight(.semibold) } icon: { StatusIcon(state: p.state) }
                        .tag(Selection.project(p.path))
                        .contextMenu {
                            Button("New Worktree…") { newWorktreeFor = p.path }
                            Button("Show in Finder") { model.showInFinder(p.path) }
                            Divider()
                            Button("Remove from List") { model.removeProject(p.path) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.projects.isEmpty {
                ContentUnavailableView("No projects", systemImage: "folder.badge.plus",
                                       description: Text("Add a git repo with the + button."))
            }
        }
    }

    private func row(_ p: Project, _ wt: Worktree) -> some View {
        let s = p.status[wt.path]
        return HStack {
            StatusIcon(state: s?.state ?? .unknown)
            Image(systemName: wt.branch == p.main ? "house" : "arrow.triangle.branch").foregroundStyle(.secondary)
            Text(wt.name).lineLimit(1)
            Spacer()
            if let n = s?.changedFiles, n > 0 {
                Text("\(n)").font(.caption2.bold()).padding(.horizontal, 5).background(.quaternary, in: Capsule())
                    .help("\(n) changed files")
            }
            AheadBehind(status: s)
        }
        .contextMenu {
            Button("Open in VS Code") { model.openInEditor(wt.path) }
            Button("Show in Finder") { model.showInFinder(wt.path) }
        }
    }

    private func expanded(_ path: String) -> Binding<Bool> {
        Binding { !collapsed.contains(path) } set: { if $0 { collapsed.remove(path) } else { collapsed.insert(path) } }
    }
}
