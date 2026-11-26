import Foundation

public struct LogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public let date: Date
    public let target: String  // "project / worktree"
    public let action: String
    public let ok: Bool
    public let detail: String

    public init(date: Date = .now, target: String, action: String, ok: Bool, detail: String = "") {
        self.date = date; self.target = target; self.action = action; self.ok = ok; self.detail = detail
    }
}

/// Keeps the log of user actions in a JSON-lines file, so the log survives a restart.
public struct ActionLog: Sendable {
    public let file: URL
    public static let keep = 500

    public init(file: URL) { self.file = file }

    public static var standard: ActionLog {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGrail")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ActionLog(file: dir.appendingPathComponent("actions.jsonl"))
    }

    /// The last `keep` entries, newest first.
    public func load() -> [LogEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).suffix(Self.keep)
            .compactMap { try? dec.decode(LogEntry.self, from: Data($0)) }.reversed()
    }

    public func append(_ e: LogEntry) {
        guard var line = try? JSONEncoder().encode(e) else { return }
        line.append(UInt8(ascii: "\n"))
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}
