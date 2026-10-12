import AppKit
import SwiftUI

// Draws the app icon: a glass orb inside a progress ring, on a deep blue-to-teal body.
// Usage: make-icon <output.png>   (1024 x 1024, transparent outside the icon body)

private let size: CGFloat = 1024
private let bodySide: CGFloat = 824
private let corner: CGFloat = 184

private struct BodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: rect)
    }
}

struct IconArt: View {
    var body: some View {
        ZStack {
            // The body casts a soft shadow onto the transparent canvas.
            BodyShape()
                .fill(.black)
                .frame(width: bodySide, height: bodySide)
                .shadow(color: .black.opacity(0.38), radius: 34, y: 26)

            ZStack {
                backdrop
                ring
                orb
                glyph
            }
            .frame(width: bodySide, height: bodySide)
            .clipShape(BodyShape())
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 3
                    )
            )
        }
        .frame(width: size, height: size)
    }

    // MARK: Layers

    private var backdrop: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.58, 0.42], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color(hex: 0x5E88FF), Color(hex: 0x4A8DFF), Color(hex: 0x36BDF2),
                    Color(hex: 0x3B63F0), Color(hex: 0x2A8CF0), Color(hex: 0x22C2D2),
                    Color(hex: 0x2A48CF), Color(hex: 0x1F86DD), Color(hex: 0x17C9AE),
                ]
            )
            // A soft bloom from the top left, like light on glass.
            RadialGradient(colors: [.white.opacity(0.42), .white.opacity(0)],
                           center: UnitPoint(x: 0.22, y: 0.08), startRadius: 0, endRadius: 560)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 36)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.75), .white],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 36, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: 0x0A2A5E).opacity(0.35), radius: 14, y: 8)
        }
        .frame(width: 590, height: 590)
    }

    private var orb: some View {
        ZStack {
            // Shadow underneath, so the disc seems to float above the ring.
            Circle()
                .fill(Color(hex: 0x0A2A6E).opacity(0.34))
                .frame(width: 400, height: 400)
                .blur(radius: 26)
                .offset(y: 26)

            // The glass body: bright where the light hits, clear towards the bottom.
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.20), .white.opacity(0.34)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 420, height: 420)

            // Light bending through the glass collects along the lower edge.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xB9F4FF).opacity(0.55), .clear],
                                     center: UnitPoint(x: 0.5, y: 1.02), startRadius: 0, endRadius: 230))
                .frame(width: 420, height: 420)
                .clipShape(Circle())

            // A bright rim that fades round the edge.
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white, .white.opacity(0.15), .white.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 8
                )
                .frame(width: 420, height: 420)

            // The specular highlight across the top.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 290, height: 120)
                .offset(y: -138)
                .blur(radius: 2)
        }
    }

    private var glyph: some View {
        // Paths are drawn from the corner of their frame, so this frame is centred on the orb.
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 74, y: 90))
                p.addLine(to: CGPoint(x: 144, y: 150))
                p.addLine(to: CGPoint(x: 74, y: 210))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))

            Path { p in
                p.move(to: CGPoint(x: 184, y: 214))
                p.addLine(to: CGPoint(x: 254, y: 214))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 40, lineCap: .round))
        }
        .frame(width: 300, height: 300)
        .shadow(color: Color(hex: 0x0A3A7A).opacity(0.45), radius: 10, y: 8)
        .offset(x: -12, y: 6)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

@MainActor
func render(to path: String) {
    let renderer = ImageRenderer(content: IconArt())
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(cg.width)x\(cg.height)")
}

guard CommandLine.arguments.count >= 2 else {
    print("usage: make-icon <output.png>")
    exit(2)
}
MainActor.assumeIsolated { render(to: CommandLine.arguments[1]) }
