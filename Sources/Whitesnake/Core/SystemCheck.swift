import Foundation

protocol SystemCheck: Sendable {
    var id: String { get }
    var title: String { get }
    var requiresAdmin: Bool { get }
    var fixButtonTitle: String? { get }
    var fixConfirmationTitle: String { get }
    var fixConfirmationMessage: String { get }
    var fixAllPriority: Int? { get }

    func check() async -> CheckResult
    func fix() async throws
    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws
}

extension SystemCheck {
    var fixButtonTitle: String? { "Fix" }

    var fixConfirmationTitle: String {
        "Apply fix for \(title)?"
    }

    var fixConfirmationMessage: String {
        "This action will run a predefined command using an absolute binary path."
    }

    var fixAllPriority: Int? { nil }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        try await fix()
    }
}
