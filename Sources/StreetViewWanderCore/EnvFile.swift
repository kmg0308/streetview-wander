import Foundation

public enum EnvFile {
    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let pieces = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                continue
            }

            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }

            if !key.isEmpty {
                values[key] = value
            }
        }

        return values
    }

    public static func parseFile(at url: URL) throws -> [String: String] {
        try parse(String(contentsOf: url, encoding: .utf8))
    }
}
