import SwiftUI

/// You, as a picture Dever makes up: a tinted disc with a few shapes placed by a seeded
/// random generator, so it is the same every launch and different for everyone. "Shuffle"
/// in Settings draws a new seed.
struct GenerativeAvatar: View {
    let seed: UInt64
    var size: CGFloat = 32

    /// The stored seed, drawn once at random.
    static let seedKey = "avatarSeed"
    static var storedSeed: UInt64 {
        if let raw = UserDefaults.standard.string(forKey: seedKey), let value = UInt64(raw) { return value }
        let fresh = UInt64.random(in: 1...UInt64.max)
        UserDefaults.standard.set(String(fresh), forKey: seedKey)
        return fresh
    }

    static func reseed() -> UInt64 {
        let fresh = UInt64.random(in: 1...UInt64.max)
        UserDefaults.standard.set(String(fresh), forKey: seedKey)
        return fresh
    }

    private struct Piece: Identifiable {
        enum Kind { case circle, square, capsule, triangle }
        let id: Int
        let kind: Kind
        let center: CGPoint   // 0…1 of the disc
        let scale: CGFloat    // of the disc's diameter
        let rotation: Angle
        let color: Color
    }

    private var design: (ground: Color, pieces: [Piece]) {
        var rng = SplitMix64(seed: seed)
        let hue = rng.unit()
        let ground = Color(hue: hue, saturation: 0.5, brightness: 0.9)
        let count = 4 + Int(rng.next() % 3)
        var pieces: [Piece] = []
        for i in 0..<count {
            let kind: Piece.Kind = [.circle, .square, .capsule, .triangle][Int(rng.next() % 4)]
            // One piece in the complementary hue, the rest deeper tones of the ground's.
            let color = i == 0
                ? Color(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.8)
                : Color(hue: (hue + rng.unit() * 0.12 - 0.06 + 1).truncatingRemainder(dividingBy: 1),
                        saturation: 0.6, brightness: 0.45 + rng.unit() * 0.3)
            pieces.append(Piece(id: i, kind: kind,
                                center: CGPoint(x: 0.15 + rng.unit() * 0.7, y: 0.15 + rng.unit() * 0.7),
                                scale: 0.28 + rng.unit() * 0.42,
                                rotation: .degrees(rng.unit() * 360),
                                color: color))
        }
        return (ground, pieces)
    }

    var body: some View {
        let d = design
        ZStack {
            Circle().fill(d.ground)
            ForEach(d.pieces) { piece in
                shape(piece.kind)
                    .fill(piece.color)
                    .frame(width: size * piece.scale, height: size * piece.scale * (piece.kind == .capsule ? 0.45 : 1))
                    .rotationEffect(piece.rotation)
                    .position(x: size * piece.center.x, y: size * piece.center.y)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func shape(_ kind: Piece.Kind) -> AnyShape {
        switch kind {
        case .circle: AnyShape(Circle())
        case .square: AnyShape(RoundedRectangle(cornerRadius: size * 0.06))
        case .capsule: AnyShape(Capsule())
        case .triangle: AnyShape(Triangle())
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A small seeded generator (SplitMix64), so the same seed draws the same avatar on every Mac.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0 ≤ x < 1
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
