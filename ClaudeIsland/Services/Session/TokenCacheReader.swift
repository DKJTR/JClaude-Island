//
//  TokenCacheReader.swift
//  ClaudeIsland
//
//  Reads /tmp/claude-island-tokens-<sessionId>.json — an opt-in per-session
//  token cache written by the user's statusline.sh. Gives us Claude Code's
//  authoritative `context_window.used_percentage` (which accounts for the
//  system prompt + tool definitions, not just the per-turn API usage the
//  JSONL exposes). If the file doesn't exist, callers fall back to the
//  JSONL-derived approximation in UsageInfo.
//
//  Cache format (written by statusline):
//    {"size": 1000000, "pct": 88, "used": 880000, "ts": 1713472800}
//

import Foundation

struct TokenCacheSnapshot: Equatable {
    /// Context window size (e.g. 200_000 or 1_000_000)
    let contextSize: Int
    /// Percentage used (integer 0–100)
    let usedPct: Int
    /// Absolute tokens currently in context
    let tokensUsed: Int
    /// Unix timestamp of the cache write
    let timestamp: TimeInterval

    /// True if this snapshot is recent enough to trust (default 5 min freshness)
    func isFresh(maxAgeSeconds: TimeInterval = 300) -> Bool {
        Date().timeIntervalSince1970 - timestamp <= maxAgeSeconds
    }
}

enum TokenCacheReader {
    /// Read the per-session token cache file for `sessionId` and return the
    /// snapshot if present and parseable. Returns nil for sessions the user
    /// hasn't opted into capturing (the common case for public users — they
    /// fall back to JSONL approximation).
    static func snapshot(for sessionId: String) -> TokenCacheSnapshot? {
        let path = "/tmp/claude-island-tokens-\(sessionId).json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let size = (obj["size"] as? NSNumber)?.intValue,
              let pct  = (obj["pct"]  as? NSNumber)?.intValue,
              let used = (obj["used"] as? NSNumber)?.intValue,
              let ts   = (obj["ts"]   as? NSNumber)?.doubleValue
        else { return nil }

        return TokenCacheSnapshot(
            contextSize: size,
            usedPct: pct,
            tokensUsed: used,
            timestamp: ts
        )
    }
}
