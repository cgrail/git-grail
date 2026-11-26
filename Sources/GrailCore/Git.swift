import Foundation

/// Git operations. Every call goes through the git or gh CLI.
public enum Git {
    @discardableResult
    static func git(_ args: [String], _ dir: String) async throws -> String {
        try await Shell.run("git", args, in: dir)
    }

    // MARK: Project

    /// The default branch of `origin`, for example "main".
    public static func mainBranch(repo: String) async -> String {
        if let ref = try? await git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], repo) {
            let name = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasPrefix("origin/") { return String(name.dropFirst(7)) }
        }
        for name in ["main", "master"] where (try? await git(["rev-parse", "--verify", "-q", "origin/\(name)"], repo)) != nil {
            return name
        }
        return "main"
    }

    /// The main repo folder for any folder inside a repo or one of its worktrees.
    public static func repoRoot(of dir: String) async throws -> String {
        let common = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], dir)
        return URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines)).deletingLastPathComponent().path
    }

    public static func worktrees(repo: String) async throws -> [Worktree] {
        Parse.worktrees(try await git(["worktree", "list", "--porcelain"], repo))
    }

    /// The folder next to the repo that holds the app's worktrees: `<parent>/<repo>.worktrees`.
    public static func worktreeFolder(repo: String) -> String {
        let url = URL(fileURLWithPath: repo)
        return url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".worktrees").path
    }

    /// Makes sure one worktree has the main branch. Creates it in the worktree folder if not.
    @discardableResult
    public static func ensureMainWorktree(repo: String, main: String) async throws -> Worktree {
        if let wt = try await worktrees(repo: repo).first(where: { $0.branch == main }) { return wt }
        let path = worktreeFolder(repo: repo) + "/" + main
        try await git(["worktree", "add", path, main], repo)
        return try await worktrees(repo: repo).first { $0.branch == main }!
    }

    /// Adds a feature worktree. A new branch starts at `origin/<main>`.
    public static func addWorktree(repo: String, branch: String, main: String) async throws -> String {
        let path = worktreeFolder(repo: repo) + "/" + branch.replacingOccurrences(of: "/", with: "-")
        let exists = (try? await git(["rev-parse", "--verify", "-q", "refs/heads/\(branch)"], repo)) != nil
        let args = exists ? [path, branch] : ["--no-track", "-b", branch, path, "origin/\(main)"]
        try await git(["worktree", "add"] + args, repo)
        return path
    }

    /// Removes a worktree. Git refuses if the worktree has changes, so no work gets lost.
    public static func removeWorktree(repo: String, path: String) async throws {
        try await git(["worktree", "remove", path], repo)
    }

    public static func fetch(repo: String) async throws {
        try await git(["fetch", "--prune", "origin"], repo)
    }

    /// Clones `owner/name` with gh into `parent` and returns the new repo path.
    public static func clone(_ nameWithOwner: String, into parent: String) async throws -> String {
        let name = nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
        let path = parent + "/" + name
        try await Shell.run("gh", ["repo", "clone", nameWithOwner, path], in: parent)
        return path
    }

    // MARK: Worktree status

    public static func changes(_ wt: String) async throws -> [FileChange] {
        Parse.status(try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], wt))
    }

    /// Compares the worktree with `base` and predicts if a rebase on `base` has conflicts.
    public static func status(_ wt: String, base: String) async -> WorktreeStatus {
        var s = WorktreeStatus()
        do {
            async let counts = git(["rev-list", "--left-right", "--count", "\(base)...HEAD"], wt)
            async let log = git(["log", Parse.logFormat, "\(base)..HEAD"], wt)
            async let files = changes(wt)
            async let redo = redoStack(wt)
            (s.behind, s.ahead) = Parse.counts(try await counts)
            s.aheadCommits = Parse.log(try await log)
            s.changedFiles = try await files.count
            s.redoCount = try await redo.count
            if s.ahead > 0 && s.behind > 0 {
                // merge-tree checks the merge in memory: exit 1 means a conflict, the worktree stays as it is.
                let r = try await Shell.exec("git", ["merge-tree", "--write-tree", "--quiet", "HEAD", base], in: wt)
                s.conflict = r.code == 1
            }
        } catch {
            s.error = "\(error)"
        }
        return s
    }

    public static func diff(_ wt: String, file: FileChange) async throws -> String {
        if file.isUntracked {
            // --no-index exits with 1 when the files differ, so read the output without the exit check.
            return try await Shell.exec("git", ["diff", "--no-color", "--no-index", "--", "/dev/null", file.path], in: wt).out
        }
        return try await git(["diff", "--no-color", "HEAD", "-M", "--"] + file.paths, wt)
    }

    // MARK: Actions

    /// Resets the main worktree to `origin/<main>`. Skips the reset if the worktree has changes.
    /// Returns false when it skipped.
    public static func syncMain(_ wt: String, main: String) async throws -> Bool {
        guard try await changes(wt).isEmpty else { return false }
        try await git(["reset", "--hard", "-q", "origin/\(main)"], wt)
        return true
    }

    /// Rebases the worktree on `base`. If the rebase stops, it aborts so the worktree stays usable.
    public static func rebase(_ wt: String, on base: String) async throws {
        do {
            try await git(["rebase", "--autostash", base], wt)
        } catch {
            _ = try? await Shell.exec("git", ["rebase", "--abort"], in: wt)
            throw error
        }
    }

    /// Commits all changes except `excluded`.
    public static func commit(_ wt: String, message: String, excluded: Set<String>) async throws {
        let all = try await changes(wt)
        let included = all.filter { !excluded.contains($0.path) }.flatMap(\.paths)
        let skipped = all.filter { excluded.contains($0.path) && !$0.isUntracked }.flatMap(\.paths)
        guard !included.isEmpty else { throw ShellError(command: "commit", code: 1, output: "No files to commit") }
        try await git(["add", "-A", "--"] + included, wt)
        if !skipped.isEmpty { try await git(["reset", "-q", "--"] + skipped, wt) }
        try await git(["commit", "-q", "-m", message], wt)
    }

    public static func push(_ wt: String) async throws {
        try await git(["push", "-u", "origin", "HEAD"], wt)
    }

    /// Opens a pull request for the current branch with gh and returns its URL.
    public static func createPullRequest(_ wt: String) async throws -> String {
        try await Shell.run("gh", ["pr", "create", "--fill"], in: wt).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Undo and redo

    /// Each worktree has its own redo stack in `git stash`, found by this tag.
    static func tag(_ wt: String) -> String { "git-grail:" + wt }

    static func redoStack(_ wt: String) async throws -> [String] {
        Parse.stashes(try await git(["stash", "list", "--format=%gd%x1f%s"], wt), tag: tag(wt))
    }

    /// Removes all changes and saves them on the redo stack.
    public static func undoAll(_ wt: String) async throws {
        guard try await !changes(wt).isEmpty else { return }
        try await git(["stash", "push", "-u", "-q", "-m", tag(wt)], wt)
    }

    /// Removes the changes of one file and saves them on the redo stack.
    public static func resetFile(_ wt: String, file: FileChange) async throws {
        try await git(["stash", "push", "-u", "-q", "-m", tag(wt), "--"] + file.paths, wt)
    }

    /// Brings back the most recent undo or file reset.
    public static func redo(_ wt: String) async throws {
        guard let ref = try await redoStack(wt).first else { return }
        try await git(["stash", "pop", "-q", ref], wt)
    }
}
