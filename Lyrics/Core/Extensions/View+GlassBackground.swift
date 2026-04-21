import SwiftUI

extension View {
    func glassScreenBackground() -> some View {
        background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.25), .pink.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
