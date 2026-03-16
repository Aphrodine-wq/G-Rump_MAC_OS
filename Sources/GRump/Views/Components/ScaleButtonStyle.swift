import SwiftUI

// MARK: - Global Scale Button Style (press-down effect on all buttons)

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: Anim.quick, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
