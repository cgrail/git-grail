import Foundation

public struct Worktree: Hashable, Sendable, Identifiable {
    public let path: String
    public let branch: String?  // nil when HEAD is detached
    public let head: String
    public var id: String { path }
    public var name: String { branch ?? "detached \(head.prefix(7))" }
}

public struct Commit: Hashable, Sendable, Identifiable {
    public let hash: String
    public let subject: String
    public let author: String
    public let date: String
    public var id: String { hash }
}

public struct FileChange: Hashable, Sendable, Identifiable {
    public let code: String  // the two-letter porcelain code, for example " M", "??", "R "
    public let path: String
    public let oldPath: String?  // set for renames and copies
    public var id: String { path }
    public var isUntracked: Bool { code == "??" }
    /// All paths git must see for this change, so a rename keeps both sides together.
    public var paths: [String] { [path] + (oldPath.map { [$0] } ?? []) }
}

public enum SyncState: Sendable {
    case upToDate, behind, conflict, unknown
}

public struct WorktreeStatus: Sendable {
    public var ahead = 0
    public var behind = 0
    public var conflict = false
    public var changedFiles = 0
    public var redoCount = 0
    public var aheadCommits: [Commit] = []
    public var error: String?

    public init() {}

    public var state: SyncState {
        if error != nil { return .unknown }
        if conflict { return .conflict }
        return behind > 0 ? .behind : .upToDate
    }
}
