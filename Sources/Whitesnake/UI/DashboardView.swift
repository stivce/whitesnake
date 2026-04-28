import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

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
                        ScrollView {
                            VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                                headerCard(isCompact: isCompact)

                                VStack(spacing: Design.rowSpacing) {
                                    ForEach(viewModel.items) { item in
                                        CheckRowView(item: item) {
                                            Task { await viewModel.fix(checkID: item.id) }
                                        }
                                    }
                                }

                                footerRow(isCompact: isCompact)
                            }
                            .padding(.horizontal, Design.contentPaddingH)
                            .padding(.top, Design.contentPaddingTop)
                            .padding(.bottom, Design.contentPaddingV)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Design.panelCornerRadius, style: .continuous))
                    }
                    .padding(Design.panelPadding)
            }
        }
        .task {
            await viewModel.refreshAll()
        }
    }

    @ViewBuilder
    private func headerCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    headerTitleBlock
                    metricsGrid(columns: 1)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        headerTitleBlock
                        Spacer()
                        headerIcon
                    }

                    metricsGrid(columns: 3)
                }
            }
        }
        .padding(Design.headerCardPadding)
        .background(headerFill, in: RoundedRectangle(cornerRadius: Design.headerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.headerCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(Design.strokeOpacity), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func footerRow(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summaryText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    FixAllButton(isEnabled: viewModel.hasFixableItems) {
                        Task { await viewModel.fixAll() }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center) {
                    Text(summaryText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    FixAllButton(isEnabled: viewModel.hasFixableItems) {
                        Task { await viewModel.fixAll() }
                    }
                }
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

    private var headerFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.white.opacity(0.04),
                Color.blue.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func metricPill(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text("\(value)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Whitesnake")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Development environment readiness for macOS")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var headerIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.45), Color.blue.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "terminal")
                .font(.system(size: 20, weight: .semibold))
        }
        .frame(width: Design.headerIconSize, height: Design.headerIconSize)
    }

    private func metricsGrid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Design.rowSpacing), count: columns),
            alignment: .leading,
            spacing: Design.rowSpacing
        ) {
            metricPill(title: "Healthy", value: healthyCount, tint: .green)
            metricPill(title: "Needs Action", value: actionCount, tint: .yellow)
            metricPill(title: "Missing", value: missingCount, tint: .red)
        }
    }

    private var healthyCount: Int {
        viewModel.items.filter { $0.status == .ok }.count
    }

    private var actionCount: Int {
        viewModel.items.filter { $0.status == .updateAvailable }.count
    }

    private var missingCount: Int {
        viewModel.items.filter {
            switch $0.status {
            case .missing, .failed:
                return true
            case .ok, .updateAvailable, .checking, .installing:
                return false
            }
        }.count
    }

    private var summaryText: String {
        if viewModel.items.contains(where: { $0.status == .installing }) {
            return "Installing selected components"
        }

        if viewModel.items.contains(where: { $0.status == .checking }) {
            return "Refreshing system state"
        }

        if missingCount > 0 || actionCount > 0 {
            return "\(missingCount + actionCount) checks need attention"
        }

        return "All tracked checks are healthy"
    }
}

private enum Design {
    static let panelCornerRadius: CGFloat = 34
    static let headerCornerRadius: CGFloat = 24
    static let rowCornerRadius: CGFloat = 18
    static let compactBreakpoint: CGFloat = 560
    static let panelPadding: CGFloat = 14
    static let headerCardPadding: CGFloat = 18
    static let contentPaddingH: CGFloat = 22
    static let contentPaddingTop: CGFloat = 58
    static let contentPaddingV: CGFloat = 22
    static let rowPaddingH: CGFloat = 14
    static let sectionSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 10
    static let headerIconSize: CGFloat = 46
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
