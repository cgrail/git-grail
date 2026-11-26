import GrailCore
import SwiftUI

/// One worktree: its state against main, its commits ahead, the changed files and their diff.
struct WorktreeView: View {
    @Environment(AppModel.self) private var model
    let wt: String
    @ViewState private var confirmRemove = false

    var body: some View {
        if let (p, w) = model.worktree(wt) {
            let s = p.status[wt] ?? WorktreeStatus()
            let isMain = w.branch == p.main
            VStack(spacing: 0) {
                header(p, s, isMain: isMain)
                if !s.aheadCommits.isEmpty {
                    DisclosureGroup("\(s.aheadCommits.count) commits ahead of main") {
                        ForEach(s.aheadCommits) { CommitRow(commit: $0) }
                    }
                    .padding(.horizontal).padding(.bottom, 8)
                }
                Divider()
                HSplitView {
                    FilesPane(wt: wt).frame(minWidth: 240, idealWidth: 320, maxWidth: 500)
                    DiffView(text: model.diff).frame(minWidth: 300, maxWidth: .infinity)
                }
            }
            .navigationTitle(w.name)
            .navigationSubtitle(wt)
            .toolbar { actions(p, s, isMain: isMain) }
            .task { await model.loadFiles(wt) }
            .confirmationDialog("Remove the worktree \(w.name)?", isPresented: $confirmRemove) {
                Button("Remove Worktree", role: .destructive) { Task { await model.removeWorktree(wt) } }
            } message: {
                Text("The branch stays. Git refuses if the worktree has changes.")
            }
        } else {
            ContentUnavailableView("Worktree not found", systemImage: "questionmark.folder")
        }
    }

    private func header(_ p: Project, _ s: WorktreeStatus, isMain: Bool) -> some View {
        HStack(spacing: 10) {
            StatusIcon(state: s.state).font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(message(s, isMain: isMain)).font(.headline)
                Text(isMain ? "Sync resets this worktree to \(p.base) every 90 seconds."
                            : "\(s.ahead) ahead · \(s.behind) behind \(p.base)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isMain && s.behind > 0 {
                Button { Task { await model.rebase(wt) } } label: {
                    Label("Rebase on main", systemImage: "arrow.triangle.pull")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(s.conflict ? .red : .accentColor)
                .help(s.conflict ? "The rebase has conflicts. The app stops it and keeps your branch as it is."
                                 : "Rebase this branch on \(p.base)")
                .disabled(model.busy)
            }
        }
        .padding()
    }

    private func message(_ s: WorktreeStatus, isMain: Bool) -> String {
        switch s.state {
        case .upToDate: return isMain ? "Main is up to date" : "Up to date with main"
        case .behind: return "\(s.behind) commits behind main. A rebase has no conflicts."
        case .conflict: return "\(s.behind) commits behind main. A rebase has conflicts. Fix them in VS Code."
        case .unknown: return s.error ?? "Status not known"
        }
    }

    @ToolbarContentBuilder
    private func actions(_ p: Project, _ s: WorktreeStatus, isMain: Bool) -> some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await model.undoAll(wt) } } label: { Label("Undo All", systemImage: "arrow.uturn.backward") }
                .help("Remove all changes. Redo brings them back.")
                .disabled(s.changedFiles == 0 || model.busy)
            Button { Task { await model.redo(wt) } } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .help(s.redoCount > 0 ? "Bring back the last removed changes (\(s.redoCount) saved)" : "Nothing to redo")
                .disabled(s.redoCount == 0 || model.busy)
            Button { model.openInEditor(wt) } label: { Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right") }
            if !isMain {
                Button { Task { await model.push(wt) } } label: { Label("Push", systemImage: "arrow.up.circle") }
                    .disabled(model.busy)
                Button { Task { await model.createPullRequest(wt) } } label: { Label("Pull Request", systemImage: "arrow.triangle.merge") }
                    .help("Push and create a pull request with gh")
                    .disabled(s.ahead == 0 || model.busy)
                Button(role: .destructive) { confirmRemove = true } label: { Label("Remove Worktree", systemImage: "trash") }
                    .disabled(wt == p.path || model.busy)
            }
        }
    }
}
