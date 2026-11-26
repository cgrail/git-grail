import AppKit
import GrailCore

/// User actions on a worktree. Each action goes to the log and refreshes the project.
extension AppModel {
    /// Runs `op`, logs the result, and refreshes. `op` can return a detail for the log.
    func perform(_ action: String, on wt: String, _ op: @escaping @Sendable () async throws -> String?) async {
        guard let (p, w) = worktree(wt) else { return }
        busy = true
        defer { busy = false }
        do {
            record(action, "\(p.name) / \(w.name)", ok: true, try await op() ?? "")
        } catch {
            fail(action, "\(p.name) / \(w.name)", error)
        }
        await refresh(p.path)
    }

    func rebase(_ wt: String) async {
        guard let base = project(ofWorktree: wt)?.base else { return }
        await perform("Rebase on main", on: wt) { try await Git.rebase(wt, on: base); return nil }
    }

    func push(_ wt: String) async {
        await perform("Push", on: wt) { try await Git.push(wt); return nil }
    }

    func createPullRequest(_ wt: String) async {
        await perform("Create pull request", on: wt) {
            try await Git.push(wt)
            return try await Git.createPullRequest(wt)
        }
    }

    func commit(_ wt: String, message: String) async {
        let skip = excluded[wt] ?? []
        await perform("Commit", on: wt) {
            try await Git.commit(wt, message: message, excluded: skip)
            return message
        }
    }

    func resetFile(_ wt: String, _ file: FileChange) async {
        await perform("Reset file", on: wt) { try await Git.resetFile(wt, file: file); return file.path }
    }

    func undoAll(_ wt: String) async {
        await perform("Undo all changes", on: wt) { try await Git.undoAll(wt); return nil }
    }

    func redo(_ wt: String) async {
        await perform("Redo changes", on: wt) { try await Git.redo(wt); return nil }
    }

    func addWorktree(project path: String, branch: String) async {
        guard let p = project(path) else { return }
        busy = true
        defer { busy = false }
        do {
            let wt = try await Git.addWorktree(repo: path, branch: branch, main: p.main)
            record("Create worktree", "\(p.name) / \(branch)", ok: true, wt)
            await refresh(path)
            selection = .worktree(wt)
        } catch {
            fail("Create worktree", "\(p.name) / \(branch)", error)
        }
    }

    func removeWorktree(_ wt: String) async {
        guard let (p, _) = worktree(wt) else { return }
        await perform("Remove worktree", on: wt) { try await Git.removeWorktree(repo: p.path, path: wt); return wt }
        selection = .project(p.path)
    }

    func openInEditor(_ wt: String) {
        let target = worktree(wt).map { "\($0.0.name) / \($0.1.name)" } ?? wt
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
            record("Open in VS Code", target, ok: false, "VS Code is not installed.")
            alert = "VS Code is not installed."
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: wt)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        record("Open in VS Code", target, ok: true)
    }

    func showInFinder(_ wt: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wt)])
    }
}
