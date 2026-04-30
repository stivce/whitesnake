import Foundation

struct Command: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]
    let timeoutSeconds: TimeInterval
    let currentDirectoryURL: URL?

    init(executableURL: URL, arguments: [String], timeoutSeconds: TimeInterval = 10, currentDirectoryURL: URL? = nil) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.currentDirectoryURL = currentDirectoryURL
    }
}

struct CommandResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunning: Sendable {
    func run(_ command: Command) async throws -> CommandResult
    func runStreaming(_ command: Command, onLine: @escaping @Sendable (CommandOutputLine) -> Void) async throws -> CommandResult
    func runPrivileged(scriptBody: String, prompt: String, timeoutSeconds: TimeInterval) async throws -> CommandResult
}

extension CommandRunning {
    func runPrivileged(scriptBody: String, prompt: String, timeoutSeconds: TimeInterval = 1800) async throws -> CommandResult {
        let escapedScript = scriptBody
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPrompt = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedScript)\" with prompt \"\(escapedPrompt)\" with administrator privileges"

        return try await run(
            Command(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", appleScript],
                timeoutSeconds: timeoutSeconds
            )
        )
    }
}

enum CommandRunnerError: Error, Equatable, LocalizedError {
    case invalidExecutablePath(String)
    case launchFailed(String)
    case timedOut(String)
    case interrupted
    case unreadableOutput

    var errorDescription: String? {
        switch self {
        case let .invalidExecutablePath(path):
            return "Refused to run non-absolute executable path: \(path)"
        case let .launchFailed(message):
            return "Failed to launch command: \(message)"
        case let .timedOut(path):
            return "Command timed out: \(path)"
        case .interrupted:
            return "Command was interrupted."
        case .unreadableOutput:
            return "Command output could not be decoded as UTF-8."
        }
    }
}

private final class CommandExecutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<CommandResult, Error>

    init(continuation: CheckedContinuation<CommandResult, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<CommandResult, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return
        }

        didResume = true
        continuation.resume(with: result)
    }
}

private final class CommandOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var totalData = Data()
    private var pendingData = Data()

    func append(_ data: Data, stream: CommandOutputStream, onLine: @escaping @Sendable (CommandOutputLine) -> Void) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        totalData.append(data)
        pendingData.append(data)

        var emittedLines: [String] = []
        while let newlineIndex = pendingData.firstIndex(of: 0x0A) {
            let lineData = pendingData.prefix(upTo: newlineIndex)
            pendingData.removeSubrange(...newlineIndex)

            if let line = String(data: lineData, encoding: .utf8) {
                emittedLines.append(line.trimmingCharacters(in: .newlines))
            }
        }
        lock.unlock()

        for line in emittedLines where !line.isEmpty {
            onLine(CommandOutputLine(stream: stream, text: line))
        }
    }

    func finish(stream: CommandOutputStream, onLine: @escaping @Sendable (CommandOutputLine) -> Void) -> String? {
        lock.lock()
        let remainingData = pendingData
        pendingData.removeAll(keepingCapacity: false)
        let finalString = String(data: totalData, encoding: .utf8)
        lock.unlock()

        if !remainingData.isEmpty,
           let line = String(data: remainingData, encoding: .utf8)?.trimmingCharacters(in: .newlines),
           !line.isEmpty {
            onLine(CommandOutputLine(stream: stream, text: line))
        }

        return finalString
    }
}

final class CommandRunner: CommandRunning, @unchecked Sendable {
    func run(_ command: Command) async throws -> CommandResult {
        try await runStreaming(command) { _ in }
    }

    func runStreaming(_ command: Command, onLine: @escaping @Sendable (CommandOutputLine) -> Void) async throws -> CommandResult {
        let executablePath = command.executableURL.path

        guard executablePath.hasPrefix("/") else {
            throw CommandRunnerError.invalidExecutablePath(executablePath)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = CommandOutputCollector()
        let stderrCollector = CommandOutputCollector()

        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let cwd = command.currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = CommandExecutionState(continuation: continuation)

                let timeoutTask = Task {
                    let timeoutNanoseconds = UInt64(command.timeoutSeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)

                    if process.isRunning {
                        process.terminate()
                        state.finish(.failure(CommandRunnerError.timedOut(executablePath)))
                    }
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        return
                    }

                    stdoutCollector.append(data, stream: .stdout, onLine: onLine)
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        return
                    }

                    stderrCollector.append(data, stream: .stderr, onLine: onLine)
                }

                process.terminationHandler = { process in
                    timeoutTask.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    stdoutCollector.append(remainingStdout, stream: .stdout, onLine: onLine)
                    stderrCollector.append(remainingStderr, stream: .stderr, onLine: onLine)

                    guard let stdout = stdoutCollector.finish(stream: .stdout, onLine: onLine),
                          let stderr = stderrCollector.finish(stream: .stderr, onLine: onLine) else {
                        state.finish(.failure(CommandRunnerError.unreadableOutput))
                        return
                    }

                    if process.terminationReason == .uncaughtSignal {
                        state.finish(.failure(CommandRunnerError.interrupted))
                        return
                    }

                    state.finish(
                        .success(
                            CommandResult(
                                exitCode: process.terminationStatus,
                                stdout: stdout,
                                stderr: stderr
                            )
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
                    timeoutTask.cancel()
                    state.finish(.failure(CommandRunnerError.launchFailed(error.localizedDescription)))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
