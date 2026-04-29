import AppKit
import SwiftUI

@MainActor
final class CloneRepoViewModel: ObservableObject {
    @Published private(set) var didCopy = false
    @Published private(set) var isCloning = false
    @Published private(set) var cloneResult: CloneResult?

    let repoURL = "https://github.com/stivce/mac.config.git"

    private let commandRunner: any CommandRunning

    init(commandRunner: any CommandRunning) {
        self.commandRunner = commandRunner
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

    func clone() async {
        guard !isCloning else { return }
        isCloning = true
        cloneResult = nil
        defer { isCloning = false }

        let downloadsDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .path
        let target = "\(downloadsDir)/mac.config"

        let script = "cd \"\(downloadsDir)\" && /usr/bin/git clone \(repoURL)"

        do {
            let result = try await commandRunner.run(
                Command(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", script],
                    timeoutSeconds: 120
                )
            )

            if result.exitCode == 0 {
                cloneResult = .success("Cloned to \(target)")
            } else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                cloneResult = .failure(stderr.isEmpty ? "git clone exited \(result.exitCode)" : stderr)
            }
        } catch {
            cloneResult = .failure(error.localizedDescription)
        }
    }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clone configuration")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Pull the macOS configuration repo into your Downloads folder.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                backButton
            }

            urlField

            if let result = model.cloneResult {
                resultBanner(result)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                FixAllButton(
                    title: model.isCloning ? "Cloning…" : "Clone",
                    isEnabled: !model.isCloning
                ) {
                    Task { await model.clone() }
                }
            }
        }
    }

    private var backButton: some View {
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
    static let compactBreakpoint: CGFloat = 560
    static let panelPadding: CGFloat = 32
    static let panelPaddingTop: CGFloat = 48
    static let contentPaddingH: CGFloat = 20
    static let contentPaddingTop: CGFloat = 20
    static let contentPaddingV: CGFloat = 20
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
