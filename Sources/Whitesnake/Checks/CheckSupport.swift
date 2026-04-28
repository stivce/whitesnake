import Foundation

enum InstallCheckError: Error, Equatable, LocalizedError {
    case homebrewMissing(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .homebrewMissing(message), let .commandFailed(message):
            return message
        }
    }
}

enum CheckSupport {
    static let brewURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    static let openURL = URL(fileURLWithPath: "/usr/bin/open")

    static func trimmedOutput(_ result: CommandResult) -> String? {
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    static func failureMessage(_ result: CommandResult, fallback: String) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? fallback : stdout
    }
}
