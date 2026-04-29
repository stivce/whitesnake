import AppKit
import SwiftUI

@MainActor
final class GenerateKeyViewModel: ObservableObject {
    @Published private(set) var publicKey: String? = nil
    @Published private(set) var isGenerating = false
    @Published private(set) var didCopy = false
    @Published private(set) var errorMessage: String? = nil

    private let commandRunner: any CommandRunning

    init(commandRunner: any CommandRunning) {
        self.commandRunner = commandRunner
        loadExistingKey()
    }

    func generateKey() async {
        guard !isGenerating else { return }
        isGenerating = true
        didCopy = false
        errorMessage = nil
        defer { isGenerating = false }

        let paths = sshPaths()

        do {
            try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Failed to access \(paths.directory.path): \(error.localizedDescription)"
            return
        }

        if FileManager.default.fileExists(atPath: paths.publicKey.path) {
            loadExistingKey()
            return
        }

        let command = Command(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh-keygen"),
            arguments: [
                "-t", "ed25519",
                "-f", paths.privateKey.path,
                "-q",
                "-N", ""
            ],
            timeoutSeconds: 30
        )

        do {
            let result = try await commandRunner.run(command)
            if result.exitCode == 0 {
                loadExistingKey()
            } else {
                errorMessage = readable(message: result.stderr)
                publicKey = nil
            }
        } catch {
            errorMessage = readable(error: error)
            publicKey = nil
        }
    }

    func copyKey() {
        guard let publicKey else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(publicKey, forType: .string)
        didCopy = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.didCopy = false
        }
    }

    private func loadExistingKey() {
        let paths = sshPaths()
        if let contents = try? String(contentsOf: paths.publicKey, encoding: .utf8) {
            publicKey = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            publicKey = nil
        }
    }

    private func sshPaths() -> (directory: URL, privateKey: URL, publicKey: URL) {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        let privateKey = directory.appendingPathComponent("id_ed25519")
        let publicKey = directory.appendingPathComponent("id_ed25519.pub")
        return (directory, privateKey, publicKey)
    }

    private func readable(message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ssh-keygen failed" : trimmed
    }

    private func readable(error: Error) -> String {
        if let runnerError = error as? CommandRunnerError {
            return runnerError.localizedDescription
        }
        return error.localizedDescription
    }
}

struct GenerateKeyView: View {
    let onBack: () -> Void
    let onNext: () -> Void
    @StateObject private var model: GenerateKeyViewModel

    init(commandRunner: any CommandRunning, onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onBack = onBack
        self.onNext = onNext
        _model = StateObject(wrappedValue: GenerateKeyViewModel(commandRunner: commandRunner))
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

            Text("Generate an SSH public key to authenticate with your repositories.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            keyDescriptionSection

            keyOutputSection
                }
                .padding(.bottom, 4)
            }

            footerRow
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generate SSH Key")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Create a new Ed25519 key pair and copy the public key to finish setup.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var keyDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FixAllButton(
                title: model.isGenerating ? "Generating…" : (model.publicKey == nil ? "Generate" : "Regenerate"),
                isEnabled: !model.isGenerating
            ) {
                Task { await model.generateKey() }
            }

            Text("We create an Ed25519 key pair in `~/.ssh`. Existing keys are left untouched; we surface the public key if it already exists.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let errorMessage = model.errorMessage {
                statusBanner(message: errorMessage, isSuccess: false)
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var keyOutputSection: some View {
        Group {
            if let publicKey = model.publicKey {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Public Key")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    HStack(alignment: .top, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(publicKey)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                        }

                        Button {
                            model.copyKey()
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
                        .help(model.didCopy ? "Copied" : "Copy public key")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
                }
                .padding(14)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
            }
        }
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
                title: "Next",
                isEnabled: model.publicKey != nil
            ) {
                onNext()
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
