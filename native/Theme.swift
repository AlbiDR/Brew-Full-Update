import AppKit
import SwiftUI

extension Color {
    /// A colour from a hex number, for example Color(hex: 0x4F8CFF).
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    static let blue = Color(hex: 0x4A8DFF)
    static let teal = Color(hex: 0x2FC4C0)
    static let mint = Color(hex: 0x4FD8A0)
    static let amber = Color(hex: 0xFFB43A)
    static let red = Color(hex: 0xF2615A)
    static let violet = Color(hex: 0x8B7BFF)
}

extension Tone {
    /// The colour the hero and the primary button take on.
    var accent: Color {
        switch self {
        case .calm: return Palette.blue
        case .active: return Palette.teal
        case .success: return Palette.mint
        case .attention: return Palette.amber
        }
    }

    /// Nine colours for the 3 x 3 mesh, row by row.
    func mesh(dark: Bool) -> [Color] {
        let hex: [UInt32]
        switch (self, dark) {
        case (.calm, false):
            hex = [0xEEF4FF, 0xD3E3FF, 0xE6F5F8,
                   0xDCE8FF, 0xA9C8FF, 0xC6ECF2,
                   0xEAF1FF, 0xBCD8FF, 0xDDF4EF]
        case (.calm, true):
            hex = [0x0A0F1F, 0x101C3E, 0x0A2330,
                   0x0F1A38, 0x1D3F86, 0x0F4D5C,
                   0x090F22, 0x16306E, 0x0B3A46]
        case (.active, false):
            hex = [0xE9F8FA, 0xC9F0F2, 0xE2F7EE,
                   0xD4F1F6, 0x8FDDE6, 0xB5F0D8,
                   0xE6F6FB, 0xA9E7EE, 0xD2F6E6]
        case (.active, true):
            hex = [0x08141C, 0x0B2A36, 0x0A2A26,
                   0x0A1F2B, 0x0F5B6B, 0x0F5C48,
                   0x07131B, 0x0D4658, 0x0B4A3A]
        case (.success, false):
            hex = [0xEBFAF1, 0xCDF2DF, 0xE4F7F0,
                   0xD8F5E5, 0x9BE3BE, 0xBDEFD8,
                   0xE8F8F0, 0xB2EBCF, 0xD9F6E8]
        case (.success, true):
            hex = [0x07150F, 0x0B2A1D, 0x0A2A28,
                   0x0A2016, 0x11613F, 0x0F5C55,
                   0x07130E, 0x0D4A32, 0x0B4A45]
        case (.attention, false):
            hex = [0xFFF4E6, 0xFFE2BF, 0xFFEBDD,
                   0xFFEAD0, 0xFFC98A, 0xFFD6C2,
                   0xFFF0E0, 0xFFD9A6, 0xFFE4D3]
        case (.attention, true):
            hex = [0x1A0F07, 0x3A2209, 0x2E1710,
                   0x2A1A0B, 0x7A4A12, 0x6A3320,
                   0x180E06, 0x5C3A0D, 0x52291A]
        }
        return hex.map { Color(hex: $0) }
    }
}

/// The soft, slowly moving colour behind the window. Liquid Glass refracts what is under it,
/// so this is what gives the glass something to show.
struct Backdrop: View {
    let tone: Tone
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshLayer(tone: tone, dark: scheme == .dark, still: reduceMotion)
                .id(tone)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 1.4), value: tone)
        .ignoresSafeArea()
    }
}

private struct MeshLayer: View {
    let tone: Tone
    let dark: Bool
    let still: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(at: t), colors: tone.mesh(dark: dark))
        }
    }

    /// The corners stay put; the edge and centre points drift in slow loops.
    private func points(at t: Double) -> [SIMD2<Float>] {
        func drift(_ base: Float, _ amp: Float, _ speed: Double, _ phase: Double) -> Float {
            base + amp * Float(sin(t * speed + phase))
        }
        return [
            [0, 0], [drift(0.5, 0.10, 0.23, 0), 0], [1, 0],
            [0, drift(0.5, 0.10, 0.19, 1.3)], [drift(0.5, 0.16, 0.17, 2.1), drift(0.5, 0.16, 0.21, 0.4)],
            [1, drift(0.5, 0.10, 0.27, 3.2)],
            [0, 1], [drift(0.5, 0.10, 0.25, 4.4), 1], [1, 1],
        ]
    }
}

extension View {
    /// A glass panel for content that floats above the backdrop.
    func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil) -> some View {
        glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
