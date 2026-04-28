import Foundation

protocol InstallProgressParsing: Sendable {
    var initialProgress: InstallProgress { get }
    func process(_ line: CommandOutputLine) -> InstallProgress?
}

private enum InstallProgressParserSupport {
    static func percentage(in text: String) -> Double? {
        let pattern = "(100(?:\\.0+)?|[0-9]{1,2}(?:\\.[0-9]+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Double(text[valueRange])
    }

    static func progress(stage: InstallStage, message: String, exactPercent: Double? = nil) -> InstallProgress {
        InstallProgress(
            stage: stage,
            fractionCompleted: stage.mappedFraction(for: exactPercent),
            message: message,
            exactPercent: exactPercent
        )
    }
}

struct BrewInstallProgressParser: InstallProgressParsing {
    let packageName: String

    var initialProgress: InstallProgress {
        InstallProgressParserSupport.progress(stage: .preparing, message: "Preparing \(packageName) installation")
    }

    func process(_ line: CommandOutputLine) -> InstallProgress? {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        let lowercased = text.lowercased()
        let percent = InstallProgressParserSupport.percentage(in: text)

        if lowercased.contains("downloading") || lowercased.contains("fetching") || lowercased.contains("curl") {
            return InstallProgressParserSupport.progress(stage: .downloading, message: text, exactPercent: percent)
        }

        if lowercased.contains("extract") || lowercased.contains("unpack") {
            return InstallProgressParserSupport.progress(stage: .extracting, message: text, exactPercent: percent)
        }

        if lowercased.contains("pouring") || lowercased.contains("installing") {
            return InstallProgressParserSupport.progress(stage: .installing, message: text, exactPercent: percent)
        }

        if lowercased.contains("summary") || lowercased.contains("caveats") || lowercased.contains("cleanup") {
            return InstallProgressParserSupport.progress(stage: .verifying, message: text)
        }

        if let percent {
            return InstallProgressParserSupport.progress(stage: .downloading, message: text, exactPercent: percent)
        }

        return InstallProgressParserSupport.progress(stage: .preparing, message: text)
    }
}

struct SoftwareUpdateProgressParser: InstallProgressParsing {
    let subject: String

    var initialProgress: InstallProgress {
        InstallProgressParserSupport.progress(stage: .preparing, message: "Preparing \(subject)")
    }

    func process(_ line: CommandOutputLine) -> InstallProgress? {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        let lowercased = text.lowercased()
        let percent = InstallProgressParserSupport.percentage(in: text)

        if lowercased.contains("download") {
            return InstallProgressParserSupport.progress(stage: .downloading, message: text, exactPercent: percent)
        }

        if lowercased.contains("extract") || lowercased.contains("preparing") {
            return InstallProgressParserSupport.progress(stage: .extracting, message: text, exactPercent: percent)
        }

        if lowercased.contains("install") {
            return InstallProgressParserSupport.progress(stage: .installing, message: text, exactPercent: percent)
        }

        if lowercased.contains("done") || lowercased.contains("complete") || lowercased.contains("finished") {
            return InstallProgressParserSupport.progress(stage: .verifying, message: text)
        }

        if let percent {
            return InstallProgressParserSupport.progress(stage: .installing, message: text, exactPercent: percent)
        }

        return InstallProgressParserSupport.progress(stage: .preparing, message: text)
    }
}

struct XcodeCLTInstallProgressParser: InstallProgressParsing {
    var initialProgress: InstallProgress {
        InstallProgressParserSupport.progress(stage: .preparing, message: "Preparing Command Line Tools installer")
    }

    func process(_ line: CommandOutputLine) -> InstallProgress? {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        return InstallProgressParserSupport.progress(stage: .waitingForUser, message: text)
    }
}
