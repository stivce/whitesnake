import AppKit
import SwiftUI

private enum CloneConstants {
    static let repoURL = "https://github.com/stivce/mac.config.git"
    static let maxConsoleLines = 500
    static let copyResetDelayNanoseconds: UInt64 = 1_500_000_000
    static let branchListMaxHeight: CGFloat = 180
    static let consoleMaxHeight: CGFloat = 220
    static let cloneTimeoutSeconds: TimeInterval = 120
    static let lsRemoteTimeoutSeconds: TimeInterval = 15
    static let playbookRunTimeoutSeconds: TimeInterval = 1800
}

struct PlaybookRole: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let tags: [String]
}

enum CloneResult: Equatable {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case let .success(message), let .failure(message):
            return message
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

enum RunResult: Equatable {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case let .success(message), let .failure(message):
            return message
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

@MainActor
final class CloneRepoViewModel: ObservableObject {
    @Published private(set) var didCopy = false
    @Published private(set) var isCloning = false
    @Published private(set) var cloneResult: CloneResult?
    @Published private(set) var repoExists = false
    @Published private(set) var availableBranches: [String] = []
    @Published var selectedBranch: String?
    @Published private(set) var isLoadingBranches = true
    @Published private(set) var availableRoles: [PlaybookRole] = []
    @Published var selectedRoleTags: Set<String> = []
    @Published private(set) var isLoadingRoles = false
    @Published private(set) var isRunning = false
    @Published private(set) var runResult: RunResult?
    @Published private(set) var consoleLines: [String] = []
    @Published var becomePassword: String = ""

    let repoURL = CloneConstants.repoURL

    private let commandRunner: any CommandRunning
    private let targetDir: String
    private let downloadsDir: String

    init(commandRunner: any CommandRunning) {
        self.commandRunner = commandRunner
        let downloads = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        self.downloadsDir = downloads.path
        self.targetDir = downloads.appendingPathComponent("mac.config").path

        repoExists = FileManager.default.fileExists(atPath: targetDir)
        if repoExists {
            loadRoles()
        }
        Task { await fetchBranches() }
    }

    func fetchBranches() async {
        isLoadingBranches = true
        defer { isLoadingBranches = false }

        do {
            let result = try await commandRunner.run(
                Command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: ["ls-remote", "--symref", repoURL, "HEAD"],
                    timeoutSeconds: CloneConstants.lsRemoteTimeoutSeconds
                )
            )
            let defaultBranch = parseDefaultBranch(from: result.stdout)

            let headsResult = try await commandRunner.run(
                Command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: ["ls-remote", "--heads", repoURL],
                    timeoutSeconds: CloneConstants.lsRemoteTimeoutSeconds
                )
            )

            let branches = parseBranches(from: headsResult.stdout)
            availableBranches = branches.sorted()
            selectedBranch = pickDefaultBranch(branches: branches, advertised: defaultBranch)
        } catch {
            availableBranches = []
            selectedBranch = nil
        }
    }

    func loadRoles() {
        guard FileManager.default.fileExists(atPath: targetDir) else { return }
        isLoadingRoles = true
        defer { isLoadingRoles = false }

        let playbookURL = URL(fileURLWithPath: "\(targetDir)/playbook.yml")
        guard let contents = try? String(contentsOf: playbookURL, encoding: .utf8) else {
            availableRoles = []
            return
        }

        let roles = Self.parseRoles(from: contents)
        availableRoles = roles
        selectedRoleTags = Set(roles.flatMap(\.tags))
    }

    func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(repoURL, forType: .string)
        didCopy = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: CloneConstants.copyResetDelayNanoseconds)
            self?.didCopy = false
        }
    }

    func clone(forceOverwrite: Bool) async {
        guard !isCloning else { return }
        isCloning = true
        cloneResult = nil
        defer { isCloning = false }

        var args = ["-C", downloadsDir, "clone"]
        if let branch = selectedBranch, !branch.isEmpty {
            args.append("-b")
            args.append(branch)
        }
        args.append(repoURL)
        args.append("mac.config")

        if forceOverwrite {
            try? FileManager.default.removeItem(atPath: targetDir)
        }

        do {
            let result = try await commandRunner.run(
                Command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: args,
                    timeoutSeconds: CloneConstants.cloneTimeoutSeconds
                )
            )

            if result.exitCode == 0 {
                cloneResult = .success("Cloned to \(targetDir)")
                repoExists = true
                loadRoles()
            } else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                cloneResult = .failure(stderr.isEmpty ? "git clone exited \(result.exitCode)" : stderr)
            }
        } catch {
            cloneResult = .failure(error.localizedDescription)
        }
    }

    func runSelectedRoles() async {
        guard !isRunning, !selectedRoleTags.isEmpty else { return }
        isRunning = true
        runResult = nil
        consoleLines = []
        defer { isRunning = false }

        let tagsArg = selectedRoleTags.sorted().joined(separator: ",")
        let ansiblePath = resolveAnsiblePath()

        let arguments = ["playbook.yml", "--tags", tagsArg]
        var additionalEnv: [String: String] = [:]
        if !becomePassword.isEmpty {
            additionalEnv["ANSIBLE_BECOME_PASS"] = becomePassword
        }

        do {
            let result = try await commandRunner.runStreaming(
                Command(
                    executableURL: URL(fileURLWithPath: ansiblePath),
                    arguments: arguments,
                    timeoutSeconds: CloneConstants.playbookRunTimeoutSeconds,
                    currentDirectoryURL: URL(fileURLWithPath: targetDir),
                    additionalEnvironment: additionalEnv
                ),
                onLine: { [weak self] line in
                    Task { @MainActor in
                        self?.appendConsoleLine(line.text)
                    }
                }
            )

            if result.exitCode == 0 {
                runResult = .success("All selected roles applied successfully")
            } else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                runResult = .failure(stderr.isEmpty ? "ansible-playbook exited \(result.exitCode)" : stderr)
            }
        } catch {
            runResult = .failure(error.localizedDescription)
        }
    }

    private func appendConsoleLine(_ line: String) {
        consoleLines.append(line)
        if consoleLines.count > CloneConstants.maxConsoleLines {
            consoleLines.removeFirst(consoleLines.count - CloneConstants.maxConsoleLines)
        }
    }

    private func resolveAnsiblePath() -> String {
        let candidates = [
            "/opt/homebrew/bin/ansible-playbook",
            "/usr/local/bin/ansible-playbook"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates[0]
    }

    private func parseDefaultBranch(from output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            // Format: "ref: refs/heads/main\tHEAD"
            if line.hasPrefix("ref: ") {
                let tabSplit = line.split(separator: "\t")
                guard let refPart = tabSplit.first else { continue }
                let ref = refPart.dropFirst("ref: ".count)
                if let branch = ref.split(separator: "/").last {
                    return String(branch)
                }
            }
        }
        return nil
    }

    private func parseBranches(from output: String) -> [String] {
        var branches: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            guard parts.count == 2 else { continue }
            let ref = parts[1]
            // Take everything after refs/heads/
            let prefix = "refs/heads/"
            if ref.hasPrefix(prefix) {
                branches.append(String(ref.dropFirst(prefix.count)))
            } else if let last = ref.split(separator: "/").last {
                branches.append(String(last))
            }
        }
        return branches
    }

    private func pickDefaultBranch(branches: [String], advertised: String?) -> String? {
        if let advertised, branches.contains(advertised) { return advertised }
        if branches.contains("main") { return "main" }
        if branches.contains("master") { return "master" }
        return branches.sorted().first
    }

    static func parseRoles(from playbook: String) -> [PlaybookRole] {
        var roles: [PlaybookRole] = []
        var currentName: String?
        var currentTags: [String] = []

        func flush() {
            if let name = currentName {
                roles.append(PlaybookRole(name: name, tags: currentTags.isEmpty ? [name] : currentTags))
            }
            currentName = nil
            currentTags = []
        }

        for rawLine in playbook.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("- role:") {
                flush()
                let value = line.dropFirst("- role:".count).trimmingCharacters(in: .whitespaces)
                currentName = value.isEmpty ? nil : value
            } else if line.hasPrefix("tags:") {
                let valuePart = line.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                if let inlineTags = parseInlineTagList(valuePart) {
                    currentTags = inlineTags
                }
            }
        }
        flush()

        return roles
    }

    private static func parseInlineTagList(_ value: String) -> [String]? {
        guard let openIdx = value.firstIndex(of: "["),
              let closeIdx = value.firstIndex(of: "]"),
              openIdx < closeIdx else { return nil }
        let inner = value[value.index(after: openIdx)..<closeIdx]
        return inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }
}

struct CloneRepoView: View {
    let onBack: () -> Void
    @StateObject private var model: CloneRepoViewModel

    init(commandRunner: any CommandRunning, onBack: @escaping () -> Void) {
        self.onBack = onBack
        _model = StateObject(wrappedValue: CloneRepoViewModel(commandRunner: commandRunner))
    }

    var body: some View {
        ZStack {
            backgroundView

            RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous)
                .fill(panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous)
                        .strokeBorder(panelStroke, lineWidth: 1)
                }
                .overlay {
                    panelContent
                        .padding(.horizontal, Design.contentPaddingH)
                        .padding(.top, Design.contentPaddingTop)
                        .padding(.bottom, Design.contentPaddingV)
                        .clipShape(RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous))
                }
                .padding(.top, Design.panelPaddingTop)
                .padding(.bottom, Design.panelPadding)
                .padding(.horizontal, Design.panelPadding)
        }
        .ignoresSafeArea()
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                    titleBlock
                    urlField
                    branchSelector

                    if let result = model.cloneResult {
                        resultBanner(result)
                    }

                    if model.repoExists {
                        rolesSection
                    }
                }
                .padding(.bottom, 4)
            }

            if model.repoExists {
                passwordField
            }

            if !model.consoleLines.isEmpty || model.isRunning {
                debugConsole
            }

            if let result = model.runResult {
                runResultBanner(result)
            }

            if model.repoExists {
                runFooterRow
            }

            footerRow
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clone configuration")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Pull the macOS configuration repo into your Downloads folder.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var cloneButtonTitle: String {
        if model.isCloning { return "Cloning…" }
        if model.repoExists { return "Overwrite" }
        return "Clone"
    }

    private var runButtonTitle: String {
        model.isRunning ? "Running…" : "Run Selected"
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            SecureField("Sudo password (required for admin roles)", text: $model.becomePassword)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textFieldStyle(.plain)
                .disabled(model.isRunning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    model.becomePassword.isEmpty ? Color.white.opacity(0.1) : Color.cyan.opacity(0.4),
                    lineWidth: 1
                )
        }
    }

    private var footerRow: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Spacer(minLength: 12)

            FixAllButton(
                title: cloneButtonTitle,
                isEnabled: !model.isCloning && !model.isRunning
            ) {
                Task { await model.clone(forceOverwrite: model.repoExists) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Design.rowPaddingH)
        .padding(.vertical, 11)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(Design.strokeOpacity), lineWidth: 1)
        }
    }

    private var runFooterRow: some View {
        HStack(alignment: .center) {
            Spacer()

            FixAllButton(
                title: runButtonTitle,
                isEnabled: !model.isRunning && !model.selectedRoleTags.isEmpty && !model.isCloning
            ) {
                Task { await model.runSelectedRoles() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Design.rowPaddingH)
        .padding(.vertical, 11)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(Design.strokeOpacity), lineWidth: 1)
        }
    }

    private var urlField: some View {
        HStack(spacing: 10) {
            Text(model.repoURL)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.copyURL()
            } label: {
                ZStack {
                    Image(systemName: "doc.on.doc")
                        .opacity(model.didCopy ? 0 : 1)
                    Image(systemName: "checkmark")
                        .opacity(model.didCopy ? 1 : 0)
                        .foregroundStyle(.green)
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(model.didCopy ? "Copied" : "Copy URL")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var branchSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)

            if model.isLoadingBranches {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading branches…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if model.availableBranches.isEmpty {
                Text("No branches found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.availableBranches, id: \.self) { branch in
                            BranchRow(
                                name: branch,
                                isSelected: model.selectedBranch == branch
                            ) {
                                model.selectedBranch = branch
                            }
                        }
                    }
                }
                .frame(maxHeight: CloneConstants.branchListMaxHeight)
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var rolesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Roles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("\(model.selectedRoleTags.count) selected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if model.isLoadingRoles {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading roles…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if model.availableRoles.isEmpty {
                Text("No roles defined in playbook.yml")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 6) {
                    ForEach(model.availableRoles) { role in
                        RoleCheckbox(role: role, selectedTags: $model.selectedRoleTags)
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func resultBanner(_ result: CloneResult) -> some View {
        statusBanner(message: result.message, isSuccess: result.isSuccess)
    }

    private func runResultBanner(_ result: RunResult) -> some View {
        statusBanner(message: result.message, isSuccess: result.isSuccess)
    }

    private func statusBanner(message: String, isSuccess: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var debugConsole: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    let text = model.consoleLines.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy all output")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.consoleLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .frame(maxHeight: CloneConstants.consoleMaxHeight)
                .padding(8)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: model.consoleLines.count) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var backgroundView: some View {
        ZStack {
            Color.clear

            GlassBackgroundView(material: .underWindowBackground, blendingMode: .behindWindow)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.025),
                            Color.cyan.opacity(0.03),
                            Color.blue.opacity(0.035),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .blur(radius: 115)
                .frame(width: 260, height: 260)
                .offset(x: -150, y: -140)

            Circle()
                .fill(Color.blue.opacity(0.11))
                .blur(radius: 125)
                .frame(width: 300, height: 300)
                .offset(x: 170, y: -110)

            Circle()
                .fill(Color.white.opacity(0.06))
                .blur(radius: 100)
                .frame(width: 220, height: 220)
                .offset(x: 160, y: 180)
        }
        .ignoresSafeArea()
    }

    private var panelFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.09),
                Color.white.opacity(0.05),
                Color.blue.opacity(0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var panelStroke: Color {
        Color.white.opacity(Design.strokeOpacity)
    }
}

private enum Design {
    static let panelCornerRadius: CGFloat = 34
    static let rowCornerRadius: CGFloat = 18
    static let panelPadding: CGFloat = 32
    static let panelPaddingTop: CGFloat = 48
    static let contentPaddingH: CGFloat = 20
    static let contentPaddingTop: CGFloat = 20
    static let contentPaddingV: CGFloat = 20
    static let rowPaddingH: CGFloat = 14
    static let sectionSpacing: CGFloat = 18
    static let strokeOpacity: Double = 0.12
}

private struct GlassBackgroundView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private struct BranchRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? AnyShapeStyle(.white.opacity(0.08))
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RoleCheckbox: View {
    let role: PlaybookRole
    @Binding var selectedTags: Set<String>

    var isSelected: Bool {
        !role.tags.isEmpty && role.tags.allSatisfy { selectedTags.contains($0) }
    }

    var body: some View {
        Button {
            if isSelected {
                for tag in role.tags {
                    selectedTags.remove(tag)
                }
            } else {
                for tag in role.tags {
                    selectedTags.insert(tag)
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.cyan)
                            .frame(width: 12, height: 12)

                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(role.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(.white.opacity(0.08))
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
