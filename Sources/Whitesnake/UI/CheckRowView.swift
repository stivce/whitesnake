import SwiftUI

struct CheckRowView: View {
    let item: DashboardCheckItem
    let fixAction: () -> Void

    @State private var shimmerPhase: CGFloat = 0

    private var isInstalling: Bool {
        item.status == .installing
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < Design.compactBreakpoint
            content(isCompact: isCompact)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(minHeight: 60)
        .onAppear(perform: startProgressAnimation)
        .onChange(of: item.status) { _, newStatus in
            if newStatus == .installing {
                startProgressAnimation()
            }
        }
    }

    @ViewBuilder
    private func content(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        statusIcon

                        VStack(alignment: .leading, spacing: 5) {
                            titleRow
                            detailsText
                        }

                        Spacer(minLength: 0)

                        if isInstalling {
                            installingBadge
                        }
                    }

                    if !isInstalling, item.canFix, let title = item.fixButtonTitle {
                        fixButton(title: title)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 5) {
                        titleRow
                        detailsText
                    }

                    Spacer(minLength: 12)

                    if isInstalling {
                        installingBadge
                    } else if item.canFix, let title = item.fixButtonTitle {
                        fixButton(title: title)
                    }
                }
            }
        }
        .padding(.horizontal, Design.rowPaddingH)
        .padding(.vertical, Design.rowPaddingV)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            if isInstalling {
                progressStrip
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(isInstalling ? 0.14 : Design.strokeOpacity), lineWidth: 1)
        }
    }

    private var rowBackground: AnyShapeStyle {
        if isInstalling {
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.07), Color.green.opacity(0.05), Color.mint.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var progressStrip: some View {
        GeometryReader { geo in
            let progress = item.installProgress?.fractionCompleted ?? item.status.defaultInstallFraction
            let clampedProgress = max(0.06, min(progress, 1.0))
            let fillWidth = geo.size.width * clampedProgress

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.04))

                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.green.opacity(0.45), Color.green.opacity(0.8), Color.mint.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: fillWidth)

                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: 60)
                    .offset(x: (fillWidth - 60) * shimmerPhase)
                    .frame(width: fillWidth, alignment: .leading)
                    .clipped()
            }
        }
        .frame(height: Design.progressStripHeight)
    }

    private var installingBadge: some View {
        Text(installingLabel)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(tintColor.opacity(0.16))
            Circle()
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)

            Image(systemName: item.status.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tintColor)
        }
        .frame(width: Design.iconSize, height: Design.iconSize)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))

            if item.requiresAdmin {
                Text("Admin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
    }

    private var detailsText: some View {
        Text(item.details ?? item.status.summaryText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(3)
    }

    @ViewBuilder
    private func fixButton(title: String) -> some View {
        Button(title, action: fixAction)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
    }

    private func startProgressAnimation() {
        guard isInstalling else { return }
        shimmerPhase = 0
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }
    }

    private var installingLabel: String {
        if let percent = item.installProgress?.exactPercent {
            return String(format: "%.0f%%", percent)
        }
        return item.installProgress?.stage.rawValue.capitalized ?? "Installing"
    }

    private var tintColor: Color {
        switch item.status {
        case .ok: return .green
        case .updateAvailable: return .yellow
        case .missing, .failed: return .red
        case .checking: return .secondary
        case .installing: return .green
        }
    }
}

private enum Design {
    static let rowCornerRadius: CGFloat = 18
    static let iconSize: CGFloat = 34
    static let progressStripHeight: CGFloat = 4
    static let compactBreakpoint: CGFloat = 430
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 8
    static let strokeOpacity: Double = 0.12
}
