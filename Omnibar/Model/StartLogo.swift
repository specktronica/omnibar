import AppKit
import Foundation

struct RGBAColor: Codable, Equatable, Sendable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    init(nsColor: NSColor) {
        let rgb = nsColor.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        func quantize(_ component: CGFloat) -> Double {
            Double(UInt8(clamping: Int((Double(component) * 255).rounded()))) / 255
        }
        self.init(
            red: quantize(rgb.redComponent),
            green: quantize(rgb.greenComponent),
            blue: quantize(rgb.blueComponent),
            alpha: quantize(rgb.alphaComponent)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        red = try container.decode(Double.self, forKey: .red)
        green = try container.decode(Double.self, forKey: .green)
        blue = try container.decode(Double.self, forKey: .blue)
        alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
    }

    nonisolated var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hexRGB: UInt32 {
        let r = UInt32(byte(red)) << 16
        let g = UInt32(byte(green)) << 8
        let b = UInt32(byte(blue))
        return r | g | b
    }

    func matches(_ other: RGBAColor) -> Bool {
        byte(red) == byte(other.red)
            && byte(green) == byte(other.green)
            && byte(blue) == byte(other.blue)
            && byte(alpha) == byte(other.alpha)
    }

    private func byte(_ component: Double) -> Int {
        Int((component * 255).rounded())
    }
}

struct StartLogoPalette: Codable, Equatable, Sendable, Hashable {
    var left: RGBAColor
    var top: RGBAColor
    var right: RGBAColor
    var bottom: RGBAColor

    static let classic = StartLogoPalette(
        left: RGBAColor(hex: 0x1070F0),
        top: RGBAColor(hex: 0x28C040),
        right: RGBAColor(hex: 0xF03018),
        bottom: RGBAColor(hex: 0xF8B000)
    )

    func matches(_ other: StartLogoPalette) -> Bool {
        left.matches(other.left)
            && top.matches(other.top)
            && right.matches(other.right)
            && bottom.matches(other.bottom)
    }
}

enum StartLogoTheme: String, CaseIterable, Identifiable, Sendable {
    case classic
    case sunset
    case ocean
    case forest
    case candy
    case neon
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .candy: "Candy"
        case .neon: "Neon"
        case .mono: "Mono"
        }
    }

    var palette: StartLogoPalette {
        switch self {
        case .classic:
            .classic
        case .sunset:
            StartLogoPalette(
                left: RGBAColor(hex: 0xF97316),
                top: RGBAColor(hex: 0xF43F5E),
                right: RGBAColor(hex: 0xEAB308),
                bottom: RGBAColor(hex: 0xFB7185)
            )
        case .ocean:
            StartLogoPalette(
                left: RGBAColor(hex: 0x0369A1),
                top: RGBAColor(hex: 0x0D9488),
                right: RGBAColor(hex: 0x38BDF8),
                bottom: RGBAColor(hex: 0xA7F3D0)
            )
        case .forest:
            StartLogoPalette(
                left: RGBAColor(hex: 0x166534),
                top: RGBAColor(hex: 0x65A30D),
                right: RGBAColor(hex: 0xCA8A04),
                bottom: RGBAColor(hex: 0x3F6212)
            )
        case .candy:
            StartLogoPalette(
                left: RGBAColor(hex: 0xEC4899),
                top: RGBAColor(hex: 0xA78BFA),
                right: RGBAColor(hex: 0x22D3EE),
                bottom: RGBAColor(hex: 0xFDBA74)
            )
        case .neon:
            StartLogoPalette(
                left: RGBAColor(hex: 0x22D3EE),
                top: RGBAColor(hex: 0xA3E635),
                right: RGBAColor(hex: 0xE879F9),
                bottom: RGBAColor(hex: 0xFACC15)
            )
        case .mono:
            StartLogoPalette(
                left: RGBAColor(hex: 0x111827),
                top: RGBAColor(hex: 0x6B7280),
                right: RGBAColor(hex: 0xD1D5DB),
                bottom: RGBAColor(hex: 0xF9FAFB)
            )
        }
    }

    static func matching(_ palette: StartLogoPalette) -> StartLogoTheme? {
        allCases.first { $0.palette.matches(palette) }
    }
}

/// Four equal circles packed in a larger circle; leftover center is a curvilinear diamond.
struct StartLogoPacking: Sendable {
    let cx: CGFloat
    let cy: CGFloat
    let outerR: CGFloat
    let innerR: CGFloat
    let offset: CGFloat

    nonisolated init(rect: NSRect, insetFactor: CGFloat = 0.07) {
        let inset = max(1 as CGFloat, min(rect.width, rect.height) * insetFactor)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        cx = bounds.midX
        cy = bounds.midY
        outerR = min(bounds.width, bounds.height) / 2
        let root2 = CGFloat(2).squareRoot()
        innerR = outerR / (1 + root2)
        offset = innerR * root2
    }

    nonisolated var outerCircle: NSBezierPath {
        oval(cx: cx, cy: cy, radius: outerR)
    }

    nonisolated func lobe(dx: CGFloat, dy: CGFloat) -> NSBezierPath {
        oval(cx: cx + dx * offset, cy: cy + dy * offset, radius: innerR)
    }

    nonisolated var centerDiamond: NSBezierPath {
        let path = NSBezierPath()
        addInnerArc(to: path, cx: cx + offset, cy: cy, from: 225, to: 135)
        addInnerArc(to: path, cx: cx, cy: cy + offset, from: 315, to: 225)
        addInnerArc(to: path, cx: cx - offset, cy: cy, from: 45, to: 315)
        addInnerArc(to: path, cx: cx, cy: cy - offset, from: 135, to: 45)
        path.close()
        return path
    }

    nonisolated private func oval(cx: CGFloat, cy: CGFloat, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
    }

    nonisolated private func addInnerArc(
        to path: NSBezierPath,
        cx: CGFloat,
        cy: CGFloat,
        from startDeg: CGFloat,
        to endDeg: CGFloat
    ) {
        let start = startDeg * .pi / 180
        let end = endDeg * .pi / 180
        var delta = end - start
        if delta > 0 { delta -= 2 * .pi }
        let steps = 20
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = start + delta * t
            let point = NSPoint(x: cx + innerR * cos(angle), y: cy + innerR * sin(angle))
            if path.elementCount == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
    }
}

enum StartLogoRenderer: Sendable {
    nonisolated static func draw(in rect: NSRect, palette: StartLogoPalette) {
        let packing = StartLogoPacking(rect: rect)
        guard packing.outerR > 0.5 else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        packing.outerCircle.addClip()

        palette.bottom.nsColor.setFill()
        packing.lobe(dx: 0, dy: -1).fill()
        palette.left.nsColor.setFill()
        packing.lobe(dx: -1, dy: 0).fill()
        palette.right.nsColor.setFill()
        packing.lobe(dx: 1, dy: 0).fill()
        palette.top.nsColor.setFill()
        packing.lobe(dx: 0, dy: 1).fill()

        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
