import Foundation

public struct ShellError: Error, CustomStringConvertible, Sendable {
    public let command: String
    public let code: Int32
    public let output: String
    public var description: String { "\(command) failed (\(code)): \(output)" }
}

public struct ShellResult: Sendable {
    public let code: Int32
    public let out: String
    public let err: String
}

/// Runs the git and gh CLIs. The app keeps no credentials: the CLIs use their own auth.
public enum Shell {
    // Apps started from Finder get a minimal PATH, so add the usual tool folders.
    static let env: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["GIT_TERMINAL_PROMPT"] = "0"  // fail fast instead of hanging on a hidden prompt
        env["GIT_OPTIONAL_LOCKS"] = "0"  // background status must not block the user's git
        return env
    }()

    /// Runs `tool args` in `dir`. Does not throw on a non-zero exit code.
    public static func exec(_ tool: String, _ args: [String], in dir: String) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = [tool] + args
                p.currentDirectoryURL = URL(fileURLWithPath: dir)
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { return cont.resume(throwing: error) }
                // Read stderr on its own thread so a full pipe cannot block the process.
                nonisolated(unsafe) var errData = Data()  // group.wait() orders the write before the read
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                cont.resume(returning: ShellResult(
                    code: p.terminationStatus,
                    out: String(decoding: outData, as: UTF8.self),
                    err: String(decoding: errData, as: UTF8.self)))
            }
        }
    }

    /// Runs `tool args` in `dir` and returns stdout. Throws on a non-zero exit code.
    @discardableResult
    public static func run(_ tool: String, _ args: [String], in dir: String) async throws -> String {
        let r = try await exec(tool, args, in: dir)
        guard r.code == 0 else {
            throw ShellError(command: ([tool] + args).joined(separator: " "), code: r.code,
                             output: (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return r.out
    }
}
