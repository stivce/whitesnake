import Foundation

struct CheckResult: Equatable, Sendable {
    let status: CheckStatus
    let details: String?

    init(status: CheckStatus, details: String? = nil) {
        self.status = status
        self.details = details
    }
}
