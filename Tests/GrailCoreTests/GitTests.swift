import Foundation
import Testing
@testable import GrailCore

/// A bare origin, a clone `repo` with the app's worktrees, and a clone `other` that plays a teammate.
struct Fixture {
    let root: String
    var repo: String { root + "/repo" }
    var other: String { root + "/other" }

    init() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("grail-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        root = String(cString: realpath(tmp.path, nil))  // git reports real paths, not /var symlinks
        try await sh(["init", "-q", "--bare", "-b", "main", "origin.git"], root)
        for dir in ["repo", "other"] {
            try await sh(["clone", "-q", "origin.git", dir], root)
            try await sh(["config", "user.name", "T"], root + "/" + dir)
            try await sh(["config", "user.email", "t@example.com"], root + "/" + dir)
            try await sh(["config", "commit.gpgsign", "false"], root + "/" + dir)
        }
        try await commit(repo, "a.txt", "one\n")
        try await sh(["push", "-q", "-u", "origin", "main"], repo)
        try await sh(["remote", "set-head", "origin", "main"], repo)
        try await sh(["pull", "-q", "origin", "main"], other)
    }

    func sh(_ args: [String], _ dir: String) async throws { try await Shell.run("git", args, in: dir) }

    func write(_ dir: String, _ file: String, _ text: String) throws {
        try text.write(toFile: dir + "/" + file, atomically: true, encoding: .utf8)
    }

    func read(_ dir: String, _ file: String) -> String? { try? String(contentsOfFile: dir + "/" + file, encoding: .utf8) }

    func commit(_ dir: String, _ file: String, _ text: String) async throws {
        try write(dir, file, text)
        try await sh(["add", file], dir)
        try await sh(["commit", "-q", "-m", "edit \(file)"], dir)
    }

    /// The teammate pushes a change to main, and `repo` fetches it.
    func teammatePushes(_ file: String, _ text: String) async throws {
        try await commit(other, file, text)
        try await sh(["push", "-q", "origin", "main"], other)
        try await Git.fetch(repo: repo)
    }

    func feature(_ name: String = "feat/x") async throws -> String {
        try await Git.addWorktree(repo: repo, branch: name, main: "main")
    }
}

@Test func findsMainBranchAndMainWorktree() async throws {
    let f = try await Fixture()
    #expect(await Git.mainBranch(repo: f.repo) == "main")
    #expect(try await Git.ensureMainWorktree(repo: f.repo, main: "main").path == f.repo)
    #expect(try await Git.repoRoot(of: try await f.feature()) == f.repo)
}

@Test func findsMainBranchWithoutOriginHead() async throws {
    let f = try await Fixture()
    try await f.sh(["remote", "set-head", "origin", "-d"], f.repo)
    #expect(await Git.mainBranch(repo: f.repo) == "main")
    try await f.sh(["remote", "remove", "origin"], f.repo)
    #expect(await Git.mainBranch(repo: f.repo) == "main")
}

@Test func createsMainWorktreeWhenNoneHasMain() async throws {
    let f = try await Fixture()
    try await f.sh(["switch", "-q", "-c", "other-work"], f.repo)
    let wt = try await Git.ensureMainWorktree(repo: f.repo, main: "main")
    #expect(wt.path == f.root + "/repo.worktrees/main")
}

@Test func addsFeatureWorktreeForNewAndExistingBranch() async throws {
    let f = try await Fixture()
    let path = try await f.feature("feat/x")
    #expect(path == f.root + "/repo.worktrees/feat-x")
    try await f.sh(["branch", "old"], f.repo)
    _ = try await f.feature("old")
    #expect(try await Git.worktrees(repo: f.repo).compactMap(\.branch) == ["main", "feat/x", "old"])
    try await Git.removeWorktree(repo: f.repo, path: path)
    #expect(try await Git.worktrees(repo: f.repo).count == 2)
}

@Test func statusShowsAheadAndBehind() async throws {
    let f = try await Fixture()
    let wt = try await f.feature()
    try await f.commit(wt, "b.txt", "mine\n")
    try await f.teammatePushes("c.txt", "theirs\n")
    let s = await Git.status(wt, base: "origin/main")
    #expect((s.ahead, s.behind, s.conflict, s.state) == (1, 1, false, .behind))
    #expect(s.aheadCommits.map(\.subject) == ["edit b.txt"])
}

@Test func statusFindsConflictAndRebaseAborts() async throws {
    let f = try await Fixture()
    let wt = try await f.feature()
    try await f.commit(wt, "a.txt", "mine\n")
    try await f.teammatePushes("a.txt", "theirs\n")
    #expect(await Git.status(wt, base: "origin/main").state == .conflict)
    await #expect(throws: ShellError.self) { try await Git.rebase(wt, on: "origin/main") }
    #expect(f.read(wt, "a.txt") == "mine\n")
    #expect(try await Git.changes(wt).isEmpty)
}

@Test func rebaseKeepsLocalChanges() async throws {
    let f = try await Fixture()
    let wt = try await f.feature()
    try await f.commit(wt, "b.txt", "mine\n")
    try f.write(wt, "b.txt", "not committed\n")
    try await f.teammatePushes("c.txt", "theirs\n")
    try await Git.rebase(wt, on: "origin/main")
    #expect(await Git.status(wt, base: "origin/main").state == .upToDate)
    #expect(f.read(wt, "b.txt") == "not committed\n")
}

@Test func statusReportsMissingBase() async throws {
    let f = try await Fixture()
    #expect(await Git.status(f.repo, base: "origin/nope").state == .unknown)
}

@Test func syncResetsCleanMainAndSkipsDirtyMain() async throws {
    let f = try await Fixture()
    try await f.teammatePushes("c.txt", "theirs\n")
    #expect(try await Git.syncMain(f.repo, main: "main"))
    #expect(f.read(f.repo, "c.txt") == "theirs\n")
    try f.write(f.repo, "a.txt", "local\n")
    #expect(try await Git.syncMain(f.repo, main: "main") == false)
    #expect(f.read(f.repo, "a.txt") == "local\n")
}

@Test func commitLeavesExcludedFilesOut() async throws {
    let f = try await Fixture()
    let wt = try await f.feature()
    try f.write(wt, "a.txt", "changed\n")
    try f.write(wt, "keep.txt", "new\n")
    try f.write(wt, "skip.txt", "new\n")
    try await f.sh(["add", "a.txt"], wt)  // a staged file the user excludes must stay out too
    try await Git.commit(wt, message: "add keep", excluded: ["a.txt", "skip.txt"])
    #expect(try await Git.changes(wt).map(\.path).sorted() == ["a.txt", "skip.txt"])
    await #expect(throws: ShellError.self) {
        try await Git.commit(wt, message: "none", excluded: ["a.txt", "skip.txt"])
    }
}

@Test func pushSendsBranchToOrigin() async throws {
    let f = try await Fixture()
    let wt = try await f.feature()
    try await f.commit(wt, "b.txt", "mine\n")
    try await Git.push(wt)
    #expect(try await Shell.run("git", ["ls-remote", "--heads", "origin", "feat/x"], in: wt).contains("feat/x"))
}

@Test func diffShowsTrackedAndUntrackedFiles() async throws {
    let f = try await Fixture()
    try f.write(f.repo, "a.txt", "two\n")
    try f.write(f.repo, "n.txt", "new\n")
    let files = try await Git.changes(f.repo)
    #expect(try await Git.diff(f.repo, file: files[0]).contains("+two"))
    #expect(try await Git.diff(f.repo, file: files[1]).contains("+new"))
}

@Test func resetFileAndUndoAllCanBeRedone() async throws {
    let f = try await Fixture()
    let wt = try await f.feature()
    try f.write(wt, "a.txt", "two\n")
    try f.write(wt, "n.txt", "new\n")
    try f.write(f.repo, "m.txt", "main work\n")  // the main worktree has its own redo stack

    try await Git.resetFile(wt, file: try await Git.changes(wt).first { $0.path == "n.txt" }!)
    #expect(try await Git.changes(wt).map(\.path) == ["a.txt"])
    try await Git.undoAll(wt)
    try await Git.undoAll(wt)  // no changes left: does nothing
    try await Git.undoAll(f.repo)
    #expect(try await Git.changes(wt).isEmpty)
    #expect(await Git.status(wt, base: "origin/main").redoCount == 2)

    try await Git.redo(wt)
    #expect(f.read(wt, "a.txt") == "two\n")
    try await Git.redo(wt)
    #expect(f.read(wt, "n.txt") == "new\n")
    try await Git.redo(wt)  // empty stack: does nothing
    #expect(f.read(f.repo, "m.txt") == nil)
}

@Test func shellReportsFailure() async throws {
    let error = await #expect(throws: ShellError.self) { try await Shell.run("git", ["nope"], in: "/") }
    #expect(error?.description.contains("git nope failed") == true)
}
