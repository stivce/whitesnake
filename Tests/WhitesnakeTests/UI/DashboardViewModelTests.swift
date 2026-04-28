import XCTest
@testable import Whitesnake

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testRefreshMarksItemCheckingBeforeCompleting() async {
        let check = MockSystemCheck(
            id: "git",
            title: "Git",
            checkResult: CheckResult(status: .ok, details: "git version 2.39.0")
        )
        let viewModel = DashboardViewModel(checks: [check])

        let task = Task {
            await viewModel.refreshAll()
        }

        await Task.yield()
        XCTAssertEqual(viewModel.items[0].status, .checking)

        check.resumeCheck()
        await task.value

        XCTAssertEqual(viewModel.items[0].status, .ok)
        XCTAssertEqual(viewModel.items[0].details, "git version 2.39.0")
    }

    func testFixRunsFixThenRefreshesStatus() async {
        let check = MockSystemCheck(
            id: "git",
            title: "Git",
            checkResult: CheckResult(status: .ok, details: "git version 2.39.0")
        )
        let viewModel = DashboardViewModel(checks: [check])

        await viewModel.fix(checkID: "git")

        XCTAssertEqual(check.fixCallCount, 1)
        XCTAssertEqual(check.checkCallCount, 1)
        XCTAssertEqual(viewModel.items[0].status, .ok)
    }
}

private final class MockSystemCheck: SystemCheck, @unchecked Sendable {
    let id: String
    let title: String
    let requiresAdmin: Bool = false

    private let checkResult: CheckResult
    private var continuation: CheckedContinuation<Void, Never>?

    var fixCallCount = 0
    var checkCallCount = 0

    init(id: String, title: String, checkResult: CheckResult) {
        self.id = id
        self.title = title
        self.checkResult = checkResult
    }

    func check() async -> CheckResult {
        checkCallCount += 1

        if continuation == nil {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        return checkResult
    }

    func fix() async throws {
        fixCallCount += 1
        resumeCheck()
    }

    func resumeCheck() {
        continuation?.resume()
        continuation = nil
    }
}
