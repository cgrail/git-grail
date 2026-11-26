import GrailCore
import SwiftUI

/// The overview of a project: all worktrees with their distance to main and their commits ahead.
struct ProjectView: View {
    @Environment(AppModel.self) private var model
    let path: String
    @Binding var newWorktreeFor: String?

    var body: some View {
        if let p = model.project(path) {
            List {
                if let error = p.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if p.mainHasChanges {
                    Label("The main worktree has changes. Sync does not reset it until you remove them.",
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                ForEach(p.worktrees) { wt in
                    let s = p.status[wt.path]
                    Section {
                        ForEach(s?.aheadCommits ?? []) { CommitRow(commit: $0) }
                    } header: {
                        Button { model.selection = .worktree(wt.path) } label: {
                            HStack {
                                StatusIcon(state: s?.state ?? .unknown)
                                Text(wt.name).font(.headline)
                                Spacer()
                                Text("\(s?.ahead ?? 0) ahead · \(s?.behind ?? 0) behind").monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(p.name)
            .navigationSubtitle(p.path)
            .toolbar {
                Button { newWorktreeFor = path } label: { Label("New Worktree", systemImage: "plus.rectangle.on.folder") }
            }
        }
    }
}

struct CommitRow: View {
    let commit: Commit

    var body: some View {
        HStack {
            Text(commit.hash).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(commit.subject).lineLimit(1)
            Spacer()
            Text("\(commit.author), \(commit.date)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
