import Foundation

enum InstallStage: String, Equatable, Sendable {
    case preparing
    case downloading
    case extracting
    case installing
    case verifying
    case waitingForUser

    var range: ClosedRange<Double> {
        switch self {
        case .preparing:
            return 0.05...0.12
        case .downloading:
            return 0.12...0.55
        case .extracting:
            return 0.55...0.72
        case .installing:
            return 0.72...0.92
        case .verifying:
            return 0.92...0.99
        case .waitingForUser:
            return 0.2...0.28
        }
    }

    var defaultFraction: Double {
        switch self {
        case .preparing:
            return 0.08
        case .downloading:
            return 0.28
        case .extracting:
            return 0.64
        case .installing:
            return 0.82
        case .verifying:
            return 0.96
        case .waitingForUser:
            return 0.24
        }
    }

    func mappedFraction(for exactPercent: Double?) -> Double {
        guard let exactPercent else {
            return defaultFraction
        }

        let clamped = max(0, min(exactPercent, 100)) / 100
        let lower = range.lowerBound
        let upper = range.upperBound
        return lower + ((upper - lower) * clamped)
    }
}

struct InstallProgress: Equatable, Sendable {
    let stage: InstallStage
    let fractionCompleted: Double
    let message: String
    let exactPercent: Double?

    init(stage: InstallStage, fractionCompleted: Double, message: String, exactPercent: Double? = nil) {
        self.stage = stage
        self.fractionCompleted = max(0, min(fractionCompleted, 1))
        self.message = message
        self.exactPercent = exactPercent
    }
}

enum CommandOutputStream: Sendable {
    case stdout
    case stderr
}

struct CommandOutputLine: Sendable {
    let stream: CommandOutputStream
    let text: String
}
