import AppKit
import GrailCore
import Observation

struct Project: Identifiable {
    let path: String
    var main = "main"
    var worktrees: [Worktree] = []
    var status: [String: WorktreeStatus] = [:]
    var error: String?
    var mainHasChanges = false
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var base: String { "origin/\(main)" }
    var mainWorktree: Worktree? { worktrees.first { $0.branch == main } }

    /// The worst state of all worktrees, so a problem shows on the project row.
    var state: SyncState {
        if error != nil { return .unknown }
        let states = worktrees.compactMap { status[$0.path]?.state }
        for s in [SyncState.conflict, .behind, .unknown] where states.contains(s) { return s }
        return .upToDate
    }
}

enum Selection: Hashable {
    case project(String), worktree(String)
}

/// App state and glue. The git logic lives in GrailCore.
@MainActor @Observable
final class AppModel {
    static let syncInterval: Duration = .seconds(90)

    var projects: [Project] = []
    var selection: Selection?
    var log: [LogEntry]
    var files: [FileChange] = []
    var selectedFile: String?
    var diff = ""
    var excluded: [String: Set<String>] = [:]  // worktree path -> files to leave out of the commit
    var busy = false
    var syncing = false
    var lastSync: Date?
    var alert: String?

    @ObservationIgnored private let actionLog = ActionLog.standard
    @ObservationIgnored private let savedKey = "projects"

    init() {
        log = actionLog.load()
        projects = (UserDefaults.standard.stringArray(forKey: savedKey) ?? []).map { Project(path: $0) }
        Task { await syncLoop() }
    }

    // MARK: Lookup

    func project(_ path: String) -> Project? { projects.first { $0.path == path } }

    func project(ofWorktree wt: String) -> Project? { projects.first { p in p.worktrees.contains { $0.path == wt } } }

    func worktree(_ wt: String) -> (Project, Worktree)? {
        guard let p = project(ofWorktree: wt), let w = p.worktrees.first(where: { $0.path == wt }) else { return nil }
        return (p, w)
    }

    var selectedWorktree: String? {
        if case .worktree(let wt) = selection { return wt }
        return nil
    }

    // MARK: Sync

    private func syncLoop() async {
        while !Task.isCancelled {
            await syncAll()
            try? await Task.sleep(for: Self.syncInterval)
        }
    }

    func syncAll() async {
        guard !syncing else { return }
        syncing = true
        await withTaskGroup(of: Void.self) { g in
            for p in projects { g.addTask { await self.sync(p.path) } }
        }
        syncing = false
        lastSync = .now
    }

    /// Fetches, resets the main worktree to origin, and loads the status of all worktrees.
    private func sync(_ path: String) async {
        if project(path)?.worktrees.isEmpty ?? false { await refresh(path) }
        guard var p = project(path) else { return }
        do {
            try await Git.fetch(repo: path)
            if let main = p.mainWorktree { p.mainHasChanges = try await !Git.syncMain(main.path, main: p.main) }
            p.error = nil
        } catch {
            p.error = "\(error)"
        }
        replace(p)
        await refresh(path)
    }

    func refresh(_ path: String) async {
        guard var p = project(path) else { return }
        do {
            p.main = await Git.mainBranch(repo: path)
            if try await !Git.worktrees(repo: path).contains(where: { $0.branch == p.main }) {
                let wt = try await Git.ensureMainWorktree(repo: path, main: p.main)
                record("Create main worktree", p.name, ok: true, wt.path)
            }
            p.worktrees = try await Git.worktrees(repo: path)
            let (wts, base) = (p.worktrees, p.base)
            p.status = await withTaskGroup(of: (String, WorktreeStatus).self) { g in
                for wt in wts { g.addTask { (wt.path, await Git.status(wt.path, base: base)) } }
                var result: [String: WorktreeStatus] = [:]
                for await (path, status) in g { result[path] = status }
                return result
            }
        } catch {
            p.error = "\(error)"
        }
        replace(p)
        if let wt = selectedWorktree, p.worktrees.contains(where: { $0.path == wt }) { await loadFiles(wt) }
    }

    func refreshSelected() async {
        switch selection {
        case .project(let path): await refresh(path)
        case .worktree(let wt): if let p = project(ofWorktree: wt) { await refresh(p.path) }
        case nil: break
        }
    }

    private func replace(_ p: Project) {
        if let i = projects.firstIndex(where: { $0.path == p.path }) { projects[i] = p }
    }

    // MARK: Files and diff

    func loadFiles(_ wt: String) async {
        let list = (try? await Git.changes(wt)) ?? []
        guard selectedWorktree == wt else { return }
        files = list
        if !list.contains(where: { $0.path == selectedFile }) { selectedFile = list.first?.path }
        await loadDiff(wt)
    }

    func loadDiff(_ wt: String) async {
        guard let f = files.first(where: { $0.path == selectedFile }) else { diff = ""; return }
        let text = (try? await Git.diff(wt, file: f)) ?? ""
        if selectedWorktree == wt && selectedFile == f.path { diff = text }
    }

    func toggleExcluded(_ wt: String, _ file: String) {
        excluded[wt, default: []].formSymmetricDifference([file])
    }

    // MARK: Projects

    func addProject(at dir: String) async {
        do {
            let root = try await Git.repoRoot(of: dir)
            if project(root) == nil {
                projects.append(Project(path: root))
                save()
                record("Add project", root, ok: true)
            }
            selection = .project(root)
            await sync(root)
        } catch {
            alert = "This folder is not a git repo:\n\(error)"
        }
    }

    func clone(_ nameWithOwner: String, into parent: String) async {
        busy = true
        defer { busy = false }
        do {
            let path = try await Git.clone(nameWithOwner, into: parent)
            record("Clone", nameWithOwner, ok: true, path)
            await addProject(at: path)
        } catch {
            fail("Clone", nameWithOwner, error)
        }
    }

    func removeProject(_ path: String) {
        projects.removeAll { $0.path == path }
        selection = nil
        save()
        record("Remove project from list", path, ok: true)
    }

    private func save() { UserDefaults.standard.set(projects.map(\.path), forKey: savedKey) }

    // MARK: Log

    func record(_ action: String, _ target: String, ok: Bool, _ detail: String = "") {
        let e = LogEntry(target: target, action: action, ok: ok, detail: detail)
        log.insert(e, at: 0)
        actionLog.append(e)
    }

    func fail(_ action: String, _ target: String, _ error: Error) {
        record(action, target, ok: false, "\(error)")
        alert = "\(action) failed.\n\n\(error)"
    }
}
