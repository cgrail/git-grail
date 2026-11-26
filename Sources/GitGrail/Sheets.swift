import AppKit
import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.log) { e in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: e.ok ? "checkmark.circle" : "xmark.circle").foregroundStyle(e.ok ? .green : .red)
                    Text(e.action).fontWeight(.medium)
                    Spacer()
                    Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                Text(e.target).font(.caption).foregroundStyle(.secondary)
                if !e.detail.isEmpty { Text(e.detail).font(.caption.monospaced()).lineLimit(4).textSelection(.enabled) }
            }
        }
        .overlay { if model.log.isEmpty { Text("No actions yet").foregroundStyle(.secondary) } }
        .navigationTitle("Action Log")
    }
}

struct NewWorktreeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: String
    @ViewState private var branch = ""

    var body: some View {
        Form {
            Text("New worktree for \(model.project(project)?.name ?? project)").font(.headline)
            TextField("Branch", text: $branch, prompt: Text("feature/my-change"))
            Text("A new branch starts at origin/\(model.project(project)?.main ?? "main"). An existing branch is checked out.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let name = branch.trimmingCharacters(in: .whitespaces)
                    dismiss()
                    Task { await model.addWorktree(project: project, branch: name) }
                }
                .disabled(branch.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct CloneSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var repo = ""
    @ViewState private var parent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer").path

    var body: some View {
        Form {
            Text("Clone with gh").font(.headline)
            TextField("Repo", text: $repo, prompt: Text("owner/name"))
            HStack {
                TextField("Folder", text: $parent)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { parent = url.path }
                }
            }
            Text("gh uses its own login. Feature worktrees go next to the clone in <name>.worktrees.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Clone") {
                    let (r, p) = (repo.trimmingCharacters(in: .whitespaces), parent)
                    dismiss()
                    Task { await model.clone(r, into: p) }
                }
                .disabled(repo.isEmpty || parent.isEmpty)
            }
        }
    }
}
