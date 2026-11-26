import Foundation

/// Parsers for machine-readable git output.
public enum Parse {
    /// Parses `git worktree list --porcelain`. Skips bare entries.
    public static func worktrees(_ text: String) -> [Worktree] {
        text.components(separatedBy: "\n\n").compactMap { block in
            var path: String?, head = "", branch: String?, bare = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
                else if line.hasPrefix("HEAD ") { head = String(line.dropFirst(5)) }
                else if line.hasPrefix("branch refs/heads/") { branch = String(line.dropFirst(18)) }
                else if line == "bare" { bare = true }
            }
            guard let path, !bare else { return nil }
            return Worktree(path: path, branch: branch, head: head)
        }
    }

    /// Parses `git status --porcelain=v1 -z`. A rename or copy entry is followed by its old path.
    public static func status(_ text: String) -> [FileChange] {
        var parts = text.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()
        var result: [FileChange] = []
        while let entry = parts.next() {
            guard entry.count > 3 else { continue }
            let code = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            let old = (code.first == "R" || code.first == "C") ? parts.next().map(String.init) : nil
            result.append(FileChange(code: code, path: path, oldPath: old))
        }
        return result
    }

    /// Parses `git rev-list --left-right --count base...HEAD` into (behind, ahead).
    public static func counts(_ text: String) -> (behind: Int, ahead: Int) {
        let n = text.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        return n.count == 2 ? (n[0], n[1]) : (0, 0)
    }

    public static let logFormat = "--format=%h%x1f%s%x1f%an%x1f%ar%x1e"

    /// Parses `git log` output made with `logFormat`.
    public static func log(_ text: String) -> [Commit] {
        text.split(separator: "\u{1e}").compactMap { record in
            let f = record.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
            guard f.count == 4 else { return nil }
            return Commit(hash: f[0], subject: f[1], author: f[2], date: f[3])
        }
    }

    /// Parses `git stash list --format=%gd%x1f%s` and returns the refs whose subject ends with `tag`.
    public static func stashes(_ text: String, tag: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            return f.count == 2 && f[1].hasSuffix(tag) ? f[0] : nil
        }
    }
}
