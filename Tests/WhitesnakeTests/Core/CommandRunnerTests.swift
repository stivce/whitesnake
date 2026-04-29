import Foundation
import Testing
@testable import Whitesnake

@Suite
struct CommandRunnerTests {
    @Test
    func rejectsRelativeExecutablePaths() async {
        let runner = CommandRunner()
        let command = Command(executableURL: URL(fileURLWithPath: "git"), arguments: ["--version"])

        await #expect(throws: CommandRunnerError.invalidExecutablePath("git")) {
            try await runner.run(command)
        }
    }

    @Test
    func capturesStandardOutput() async throws {
        let runner = CommandRunner()
        let result = try await runner.run(
            Command(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["hello"],
                timeoutSeconds: 1
            )
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello")
        #expect(result.stderr.isEmpty)
    }

    @Test
    func timesOutLongRunningCommands() async {
        let runner = CommandRunner()
        let command = Command(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeoutSeconds: 0.1
        )

        await #expect(throws: CommandRunnerError.timedOut("/bin/sleep")) {
            try await runner.run(command)
        }
    }
}
