import AppKit
import SwiftUI

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
    @Published private(set) var hasCloned = false

    let repoURL = "https://github.com/stivce/mac.config.git"

    private let commandRunner: any CommandRunning
    private let targetDir: String

    init(commandRunner: any CommandRunning) {
        self.commandRunner = commandRunner
        self.targetDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/mac.config")
            .path
        checkIfRepoExists()
        if repoExists {
            fetchRoles()
        }
        fetchBranches()
    }

    private func checkIfRepoExists() {
        repoExists = FileManager.default.fileExists(atPath: targetDir)
    }

    func fetchBranches() {
        Task {
            do {
                let result = try await commandRunner.run(
                    Command(
                        executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                        arguments: ["ls-remote", "--heads", repoURL],
                        timeoutSeconds: 15
                    )
                )

                var branches: [String] = []
                for line in result.stdout.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "\t")
                    if parts.count == 2 {
                        let ref = parts[1]
                        if let branch = ref.split(separator: "/").last {
                            branches.append(String(branch))
                        }
                    }
                }

                await MainActor.run {
                    self.availableBranches = branches.sorted()
                    self.selectedBranch = branches.contains("main") ? "main" : branches.first
                    self.isLoadingBranches = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingBranches = false
                }
            }
        }
    }

    func fetchRoles() {
        guard FileManager.default.fileExists(atPath: targetDir) else { return }
        isLoadingRoles = true

        Task {
            do {
                let playbookPath = "\(targetDir)/playbook.yml"
                let result = try await commandRunner.run(
                    Command(
                        executableURL: URL(fileURLWithPath: "/bin/cat"),
                        arguments: [playbookPath],
                        timeoutSeconds: 5
                    )
                )

                var roles: [PlaybookRole] = []
                var currentRole: String?
                var currentTags: [String] = []

                for line in result.stdout.split(whereSeparator: \.isNewline) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    if trimmed.hasPrefix("- role:"), let role = trimmed.split(separator: ":").dropFirst().first {
                        if let r = currentRole {
                            roles.append(PlaybookRole(name: r, tags: currentTags.isEmpty ? [r] : currentTags))
                        }
                        currentRole = String(role.trimmingCharacters(in: .whitespaces))
                        currentTags = []
                    } else if trimmed.hasPrefix("tags:"), let tagStr = trimmed.split(separator: "[").last?.split(separator: "]").first {
                        currentTags = tagStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    }
                }

                if let r = currentRole {
                    roles.append(PlaybookRole(name: r, tags: currentTags.isEmpty ? [r] : currentTags))
                }

                await MainActor.run {
                    self.availableRoles = roles
                    self.selectedRoleTags = Set(roles.flatMap(\.tags))
                    self.isLoadingRoles = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingRoles = false
                }
            }
        }
    }

    func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(repoURL, forType: .string)
        didCopy = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.didCopy = false
        }
    }

    func clone(forceOverwrite: Bool) async {
        guard !isCloning else { return }
        isCloning = true
        cloneResult = nil
        defer { isCloning = false }

        let downloadsDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .path

        let removeIfNeeded = forceOverwrite
            ? "/bin/rm -rf \"\(downloadsDir)/mac.config\" && "
            : ""

        let branchArg = selectedBranch.flatMap { " -b \($0)" } ?? ""

        let script = "cd \"\(downloadsDir)\" && \(removeIfNeeded)/usr/bin/git clone\(branchArg) \(repoURL)"

        do {
            let result = try await commandRunner.run(
                Command(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", script],
                    timeoutSeconds: 120
                )
            )

            if result.exitCode == 0 {
                cloneResult = .success("Cloned to \(targetDir)")
                repoExists = true
                hasCloned = true
                fetchRoles()
            } else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                cloneResult = .failure(stderr.isEmpty ? "git clone exited \(result.exitCode)" : stderr)
            }
        } catch {
            cloneResult = .failure(error.localizedDescription)
        }
    }

    func runSelectedRoles() async {
        guard !isRunning && !selectedRoleTags.isEmpty else { return }
        isRunning = true
        runResult = nil
        defer { isRunning = false }

        let tagsArg = selectedRoleTags.joined(separator: ",")
        let script = "cd \"\(targetDir)\" && /opt/homebrew/bin/ansible-playbook playbook.yml --tags \"\(tagsArg)\""

        do {
            let result = try await commandRunner.run(
                Command(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", script],
                    timeoutSeconds: 600
                )
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
}

struct PlaybookRole: Identifiable {
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

struct CloneRepoView: View {
    let onBack: () -> Void
    @StateObject private var model: CloneRepoViewModel

    init(commandRunner: any CommandRunning, onBack: @escaping () -> Void) {
        self.onBack = onBack
        _model = StateObject(wrappedValue: CloneRepoViewModel(commandRunner: commandRunner))
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < Design.compactBreakpoint

            ZStack {
                backgroundView

                RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous)
                    .fill(panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous)
                            .strokeBorder(panelStroke, lineWidth: 1)
                    }
                    .overlay {
                        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                            headerCard(isCompact: isCompact)
                        }
                        .padding(.horizontal, Design.contentPaddingH)
                        .padding(.top, Design.contentPaddingTop)
                        .padding(.bottom, Design.contentPaddingV)
                        .clipShape(RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous))
                    }
                    .padding(.top, Design.panelPaddingTop)
                    .padding(.bottom, Design.panelPadding)
                    .padding(.horizontal, Design.panelPadding)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func headerCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clone configuration")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Pull the macOS configuration repo into your Downloads folder.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            urlField

            branchSelector

            if let result = model.cloneResult {
                resultBanner(result)
            }

            if model.repoExists || model.hasCloned {
                rolesSection

                runFooterRow(isCompact: isCompact)
            }

            if let result = model.runResult {
                runResultBanner(result)
            }

            Spacer(minLength: 0)

            footerRow(isCompact: isCompact)
        }
    }

    private var buttonTitle: String {
        if model.isCloning {
            return "Cloning…"
        }
        if model.isRunning {
            return "Running…"
        }
        if model.repoExists {
            return "Overwrite"
        }
        return "Clone"
    }

    private var runButtonTitle: String {
        if model.isRunning {
            return "Running…"
        }
        return "Run Selected"
    }

    @ViewBuilder
    private func footerRow(isCompact: Bool) -> some View {
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

            Spacer(minLength: 12)

            FixAllButton(
                title: buttonTitle,
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

    @ViewBuilder
    private func runFooterRow(isCompact: Bool) -> some View {
        HStack(alignment: .center) {
            Spacer()

            FixAllButton(
                title: runButtonTitle,
                isEnabled: !model.isRunning && !model.selectedRoleTags.isEmpty
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

    @ViewBuilder
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
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
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
        HStack(spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.isSuccess ? .green : .orange)
            Text(result.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func runResultBanner(_ result: RunResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.isSuccess ? .green : .orange)
            Text(result.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    static let compactBreakpoint: CGFloat = 560
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
        }
        .buttonStyle(.plain)
    }
}

private struct RoleCheckbox: View {
    let role: PlaybookRole
    @Binding var selectedTags: Set<String>

    var isSelected: Bool {
        role.tags.allSatisfy { selectedTags.contains($0) }
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
        }
        .buttonStyle(.plain)
    }
}
