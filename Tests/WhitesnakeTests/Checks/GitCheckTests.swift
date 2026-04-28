import XCTest
@testable import Whitesnake

final class GitCheckTests: XCTestCase {
    func testReturnsOkWhenGitVersionSucceeds() async {
        let runner = MockCommandRunner(
            results: [
                .success(CommandResult(exitCode: 0, stdout: "git version 2.39.0\n", stderr: ""))
            ]
        )
        let check = GitCheck(commandRunner: runner)

        let result = await check.check()

        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.details, "git version 2.39.0")
    }

    func testReturnsMissingWhenNoGitBinaryLaunches() async {
        let runner = MockCommandRunner(
            results: [
                .failure(CommandRunnerError.launchFailed("missing")),
                .failure(CommandRunnerError.launchFailed("missing"))
            ]
        )
        let check = GitCheck(commandRunner: runner)

        let result = await check.check()

        XCTAssertEqual(result.status, .missing)
    }

    func testFixThrowsWhenHomebrewIsMissing() async {
        let runner = MockCommandRunner(results: [])
        let check = GitCheck(
            commandRunner: runner,
            brewURL: URL(fileURLWithPath: "/tmp/whitesnake-tests/nonexistent-brew")
        )

        do {
            try await check.fix()
            XCTFail("Expected missing Homebrew error")
        } catch let error as GitCheckError {
            XCTAssertEqual(error, .homebrewMissing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    private var results: [Result<CommandResult, Error>]

    init(results: [Result<CommandResult, Error>]) {
        self.results = results
    }

    func run(_ command: Command) async throws -> CommandResult {
        guard !results.isEmpty else {
            throw CommandRunnerError.launchFailed("No mock result configured")
        }

        let result = results.removeFirst()
        return try result.get()
    }

    func runStreaming(_ command: Command, onLine: @escaping @Sendable (CommandOutputLine) -> Void) async throws -> CommandResult {
        try await run(command)
    }
}
