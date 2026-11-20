import Foundation

/// Turns a coach reply (light Markdown) into the plain text that is read aloud. Mirrors
/// speechText() in backend/src/text.ts, so the app's audio cache key matches what was spoken.
public enum SpeechText {
    private static let rules: [(pattern: String, template: String, options: NSRegularExpression.Options)] = [
        ("```[\\s\\S]*?```", " ", []), // code blocks
        ("`([^`]*)`", "$1", []), // inline code
        ("!\\[([^\\]]*)\\]\\([^)]*\\)", "$1", []), // images
        ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1", []), // links
        ("^\\s{0,3}#{1,6}\\s+", "", [.anchorsMatchLines]), // headings
        ("^\\s*[-*+]\\s+", "", [.anchorsMatchLines]), // bullets
        ("^\\s*(\\d+)[.)]\\s+", "$1. ", [.anchorsMatchLines]), // numbered lists
        ("(\\*\\*|__)(.*?)\\1", "$2", []), // bold
        ("(\\*|_)(\\S(?:.*?\\S)?)\\1", "$2", []), // italics
        ("°F", " degrees", []),
        ("[ \\t]+", " ", []),
        ("\\n{2,}", "\n\n", []),
    ]

    public static func plain(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: rule.template)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A stable cache key for a reply's audio (FNV-1a over the spoken text).
    public static func cacheKey(_ markdown: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in plain(markdown).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
