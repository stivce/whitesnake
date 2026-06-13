import AppKit
import SwiftUI

struct RebootView: View {
    var body: some View {
        ZStack {
            backgroundView

            RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous)
                .fill(panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(Design.strokeOpacity), lineWidth: 1)
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
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 96, height: 96)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 10) {
                    Text("Setup complete")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Restart your Mac to apply all changes.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                FixAllButton(title: "Restart Now", isEnabled: true) {
                    reboot()
                }

                Button("Later") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Design.rowPaddingH)
            .padding(.vertical, 16)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(Design.strokeOpacity), lineWidth: 1)
            }
        }
    }

    private func reboot() {
        let script = NSAppleScript(source: "tell application \"System Events\" to restart")
        script?.executeAndReturnError(nil)
    }

    private var backgroundView: some View {
        ZStack {
            Color.clear

            GlassBackgroundView(material: .underWindowBackground, blendingMode: .behindWindow)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.025),
                            Color.green.opacity(0.03),
                            Color.cyan.opacity(0.025),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            Circle()
                .fill(Color.green.opacity(0.1))
                .blur(radius: 115)
                .frame(width: 280, height: 280)
                .offset(x: -130, y: -120)

            Circle()
                .fill(Color.cyan.opacity(0.09))
                .blur(radius: 125)
                .frame(width: 300, height: 300)
                .offset(x: 170, y: -100)

            Circle()
                .fill(Color.white.opacity(0.05))
                .blur(radius: 100)
                .frame(width: 220, height: 220)
                .offset(x: 150, y: 190)
        }
        .ignoresSafeArea()
    }

    private var panelFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.09),
                Color.white.opacity(0.05),
                Color.green.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
