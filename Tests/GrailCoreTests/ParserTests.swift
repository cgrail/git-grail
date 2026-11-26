import Foundation
import Testing
@testable import GrailCore

@Test func parsesWorktreesAndSkipsBare() {
    let text = """
    worktree /r/bare
    bare

    worktree /r/main
    HEAD abc123
    branch refs/heads/main

    worktree /r/x
    HEAD def456
    detached

    """
    let wts = Parse.worktrees(text)
    #expect(wts.map(\.path) == ["/r/main", "/r/x"])
    #expect(wts[0].branch == "main")
    #expect(wts[1].name == "detached def456")
    #expect(wts[0].id == "/r/main")
}

@Test func parsesStatusWithRename() {
    let files = Parse.status(" M a.txt\0R  new.txt\0old.txt\0?? n.txt\0")
    #expect(files.map(\.path) == ["a.txt", "new.txt", "n.txt"])
    #expect(files[1].paths == ["new.txt", "old.txt"])
    #expect(files[2].isUntracked)
    #expect(files[0].id == "a.txt")
}

@Test func parsesCounts() {
    #expect(Parse.counts("3\t5\n") == (3, 5))
    #expect(Parse.counts("") == (0, 0))
}

@Test func parsesLog() {
    let c = Parse.log("abc\u{1f}Fix it\u{1f}Ann\u{1f}2 days ago\u{1e}\nbad\u{1e}")
    #expect(c == [Commit(hash: "abc", subject: "Fix it", author: "Ann", date: "2 days ago")])
    #expect(c[0].id == "abc")
}

@Test func findsOnlyStashesWithTag() {
    let text = "stash@{0}\u{1f}On f: git-grail:/a\nstash@{1}\u{1f}On f: git-grail:/x/a\nstash@{2}\u{1f}On f: git-grail:/a"
    #expect(Parse.stashes(text, tag: "git-grail:/a") == ["stash@{0}", "stash@{2}"])
}

@Test func stateShowsWorstCase() {
    var s = WorktreeStatus()
    #expect(s.state == .upToDate)
    s.behind = 1
    #expect(s.state == .behind)
    s.conflict = true
    #expect(s.state == .conflict)
    s.error = "x"
    #expect(s.state == .unknown)
}

@Test func actionLogKeepsEntriesNewestFirst() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    let log = ActionLog(file: file)
    log.append(LogEntry(target: "p", action: "one", ok: true))
    log.append(LogEntry(target: "p", action: "two", ok: false, detail: "err"))
    #expect(log.load().map(\.action) == ["two", "one"])
}

@Test func standardActionLogLivesInApplicationSupport() {
    #expect(ActionLog.standard.file.path.hasSuffix("Application Support/GitGrail/actions.jsonl"))
}
