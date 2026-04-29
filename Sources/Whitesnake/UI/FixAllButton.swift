import SwiftUI

struct FixAllButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    init(title: String = "Patch", isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(backgroundStyle, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(isEnabled ? 0.18 : 0.1), lineWidth: 1)
            }
            .disabled(!isEnabled)
    }

    private var backgroundStyle: AnyShapeStyle {
        if isEnabled {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(.ultraThinMaterial)
    }
}
