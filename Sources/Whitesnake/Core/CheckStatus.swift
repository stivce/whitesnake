import Foundation

enum CheckStatus: Equatable, Sendable {
    case ok
    case updateAvailable
    case missing
    case checking
    case installing
    case failed(String)

    var summaryText: String {
        switch self {
        case .ok:
            return "Installed and up to date"
        case .updateAvailable:
            return "Update available"
        case .missing:
            return "Missing"
        case .checking:
            return "Checking"
        case .installing:
            return "Installing"
        case let .failed(message):
            return message
        }
    }

    var symbolName: String {
        switch self {
        case .ok:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "exclamationmark.triangle.fill"
        case .missing, .failed:
            return "xmark.circle.fill"
        case .checking:
            return "circle.fill"
        case .installing:
            return "arrow.down.circle.fill"
        }
    }

    var defaultInstallFraction: Double {
        switch self {
        case .installing:
            return 0.18
        case .checking:
            return 0.08
        case .ok:
            return 1
        case .updateAvailable:
            return 0.7
        case .missing, .failed:
            return 0
        }
    }
}
