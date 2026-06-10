import Foundation

/// Canonical filesystem locations under the user's home directory for Perch-owned data.
enum PerchPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var perchDir: URL {
        home.appendingPathComponent(".perch", isDirectory: true)
    }

    static var agentAuditLog: URL {
        perchDir.appendingPathComponent("agent-audit.jsonl")
    }

    /// Ensures `~/.perch` exists. Safe to call repeatedly.
    static func ensurePerchDir() {
        try? FileManager.default.createDirectory(at: perchDir, withIntermediateDirectories: true)
    }
}
