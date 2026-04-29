import Foundation
import Testing
@testable import Whitesnake

@Suite
struct GitCheckTests {
    @Test
    func returnsOkWhenGitVersionSucceeds() async {
        let runner = MockCommandRunner(
            results: [
                .success(CommandResult(exitCode: 0, stdout: "git version 2.39.0\n", stderr: ""))
            ]
        )
        let check = GitCheck(commandRunner: runner)

        let result = await check.check()

        #expect(result.status == .ok)
        #expect(result.details == "git version 2.39.0")
    }

    @Test
    func returnsMissingWhenNoGitBinaryLaunches() async {
        let runner = MockCommandRunner(
            results: [
                .failure(CommandRunnerError.launchFailed("missing")),
                .failure(CommandRunnerError.launchFailed("missing"))
            ]
        )
        let check = GitCheck(commandRunner: runner)

        let result = await check.check()

        #expect(result.status == .missing)
    }

    @Test
    func fixThrowsWhenHomebrewIsMissing() async {
        let runner = MockCommandRunner(results: [])
        let check = GitCheck(
            commandRunner: runner,
            brewURL: URL(fileURLWithPath: "/tmp/whitesnake-tests/nonexistent-brew")
        )

        await #expect(throws: GitCheckError.homebrewMissing) {
            try await check.fix()
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
