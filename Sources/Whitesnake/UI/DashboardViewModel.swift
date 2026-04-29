import Foundation

struct DashboardCheckItem: Identifiable, Equatable {
    let id: String
    let title: String
    let requiresAdmin: Bool
    let fixButtonTitle: String?
    let fixConfirmationTitle: String
    let fixConfirmationMessage: String
    let fixAllPriority: Int?
    var status: CheckStatus
    var details: String?
    var installProgress: InstallProgress?

    var canFix: Bool {
        guard fixButtonTitle != nil else {
            return false
        }

        switch status {
        case .missing, .updateAvailable, .failed:
            return true
        case .ok, .checking, .installing:
            return false
        }
    }

    var isIncludedInFixAll: Bool {
        fixAllPriority != nil && canFix
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var items: [DashboardCheckItem]
    private(set) var hasLoaded = false

    private let checks: [any SystemCheck]

    init(checks: [any SystemCheck]) {
        self.checks = checks
        self.items = checks.map {
            DashboardCheckItem(
                id: $0.id,
                title: $0.title,
                requiresAdmin: $0.requiresAdmin,
                fixButtonTitle: $0.fixButtonTitle,
                fixConfirmationTitle: $0.fixConfirmationTitle,
                fixConfirmationMessage: $0.fixConfirmationMessage,
                fixAllPriority: $0.fixAllPriority,
                status: .checking,
                details: nil,
                installProgress: nil
            )
        }
    }

    var hasFixableItems: Bool {
        items.contains(where: \.isIncludedInFixAll)
    }

    var fixAllConfirmationMessage: String {
        let ordered = items
            .filter { $0.fixAllPriority != nil }
            .sorted { ($0.fixAllPriority ?? .max) < ($1.fixAllPriority ?? .max) }
            .map(\.title)
            .joined(separator: ", ")
        let manual = items
            .filter { $0.fixAllPriority == nil }
            .map(\.title)
            .joined(separator: ", ")
        var message = "Whitesnake will run automatic fixes in this order: \(ordered)."
        if !manual.isEmpty {
            message += " Manual flows (\(manual)) remain separate."
        }
        return message
    }

    func refreshAll() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        for check in checks {
            updateStatus(for: check.id, status: .checking, details: nil, installProgress: nil)
            let result = await check.check()
            updateStatus(for: check.id, status: result.status, details: result.details, installProgress: nil)
        }
    }

    func fix(checkID: String) async {
        guard let check = checks.first(where: { $0.id == checkID }) else {
            return
        }

        updateStatus(for: check.id, status: .installing, details: "Preparing installation", installProgress: nil)

        do {
            try await check.fix { [weak self] progress in
                Task { @MainActor in
                    self?.updateStatus(for: check.id, status: .installing, details: progress.message, installProgress: progress)
                }
            }
            let result = await check.check()
            updateStatus(for: check.id, status: result.status, details: result.details, installProgress: nil)
        } catch {
            updateStatus(for: check.id, status: .failed(error.localizedDescription), details: nil, installProgress: nil)
        }
    }

    func fixAll() async {
        let orderedItems = items
            .filter(\.isIncludedInFixAll)
            .sorted { lhs, rhs in
                (lhs.fixAllPriority ?? .max) < (rhs.fixAllPriority ?? .max)
            }

        for item in orderedItems {
            await fix(checkID: item.id)
        }
    }

    private func updateStatus(for checkID: String, status: CheckStatus, details: String?, installProgress: InstallProgress?) {
        guard let index = items.firstIndex(where: { $0.id == checkID }) else {
            return
        }

        items[index].status = status
        items[index].details = details
        items[index].installProgress = installProgress
    }
}
