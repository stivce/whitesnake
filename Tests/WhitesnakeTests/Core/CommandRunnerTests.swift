import XCTest
@testable import Whitesnake

final class CommandRunnerTests: XCTestCase {
    func testRejectsRelativeExecutablePaths() async {
        let runner = CommandRunner()
        let command = Command(executableURL: URL(fileURLWithPath: "git"), arguments: ["--version"])

        do {
            _ = try await runner.run(command)
            XCTFail("Expected invalid executable path error")
        } catch let error as CommandRunnerError {
            XCTAssertEqual(error, .invalidExecutablePath("git"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCapturesStandardOutput() async throws {
        let runner = CommandRunner()
        let result = try await runner.run(
            Command(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["hello"],
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testTimesOutLongRunningCommands() async {
        let runner = CommandRunner()
        let command = Command(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeoutSeconds: 0.1
        )

        do {
            _ = try await runner.run(command)
            XCTFail("Expected timeout error")
        } catch let error as CommandRunnerError {
            XCTAssertEqual(error, .timedOut("/bin/sleep"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
