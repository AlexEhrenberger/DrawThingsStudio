import CoreGraphics
import Foundation

/// Größenstufe wie in Draw Things (Klein · Normal · Groß).
enum SizeTier: String, CaseIterable, Identifiable {
    case small, normal, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Klein"
        case .normal: "Normal"
        case .large: "Groß"
        }
    }
}

/// Seitenverhältnisse genau so, wie Draw Things sie anbietet – mit den Pixelgrößen je Stufe
/// (abgelesen aus Draw Things, 12.10.2026). Nur diese Größen verarbeitet Draw Things ohne Probleme,
/// deshalb geht jedes Bild in genau einer davon an Draw Things.
struct AspectRatio: Hashable, Identifiable {
    let width: Int
    let height: Int
    let name: String
    let small: CGSize
    /// 16:9 und 9:16 gibt es in Draw Things nicht als „Normal“ – dort springt es auf „Klein“.
    let normal: CGSize?
    let large: CGSize

    init(_ width: Int, _ height: Int, _ name: String, small: (Int, Int), normal: (Int, Int)?, large: (Int, Int)) {
        self.width = width
        self.height = height
        self.name = name
        self.small = CGSize(width: small.0, height: small.1)
        self.normal = normal.map { CGSize(width: $0.0, height: $0.1) }
        self.large = CGSize(width: large.0, height: large.1)
    }

    var id: String { "\(width):\(height)" }
    var label: String { "\(width):\(height)" }
    var value: Double { Double(width) / Double(height) }

    static func == (lhs: AspectRatio, rhs: AspectRatio) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var orientation: String {
        if width == height { return "square" }
        return width > height ? "landscape" : "portrait"
    }

    func offers(_ tier: SizeTier) -> Bool {
        tier != .normal || normal != nil
    }

    /// Stufe, die Draw Things tatsächlich nimmt (Normal fehlt → Klein).
    func effectiveTier(_ tier: SizeTier) -> SizeTier {
        offers(tier) ? tier : .small
    }

    /// Breite × Höhe in Pixeln für Draw Things.
    func pixelSize(_ tier: SizeTier) -> CGSize {
        switch effectiveTier(tier) {
        case .small: small
        case .normal: normal ?? small
        case .large: large
        }
    }

    /// Die Pixelgrößen weichen leicht vom Nennverhältnis ab (4:5 Klein ist 704 × 832) – alle zählen beim Zuordnen.
    private var matchValues: [Double] {
        [value] + [small, normal, large].compactMap { $0 }.map { $0.width / $0.height }
    }

    /// Abstand im Logarithmus, damit 1:2 und 2:1 gleich weit von 1:1 entfernt sind.
    func distance(to ratio: Double) -> Double {
        let target = log(ratio)
        return matchValues.map { abs(log($0) - target) }.min() ?? .infinity
    }

    /// Reihenfolge wie in Draw Things.
    static let all: [AspectRatio] = [
        AspectRatio(1, 2, "Schmal hoch", small: (512, 1024), normal: (704, 1408), large: (896, 1792)),
        AspectRatio(2, 3, "Foto hoch", small: (512, 768), normal: (768, 1152), large: (1024, 1536)),
        AspectRatio(3, 4, "Hochformat", small: (576, 768), normal: (768, 1024), large: (960, 1280)),
        AspectRatio(4, 5, "Porträt", small: (704, 832), normal: (896, 1152), large: (1024, 1280)),
        AspectRatio(1, 1, "Quadrat", small: (768, 768), normal: (1024, 1024), large: (1280, 1280)),
        AspectRatio(5, 4, "Quer kompakt", small: (832, 704), normal: (1152, 896), large: (1280, 1024)),
        AspectRatio(4, 3, "Querformat", small: (768, 576), normal: (1024, 768), large: (1280, 960)),
        AspectRatio(3, 2, "Foto quer", small: (768, 512), normal: (1152, 768), large: (1536, 1024)),
        AspectRatio(2, 1, "Panorama", small: (1024, 512), normal: (1408, 704), large: (1792, 896)),
        AspectRatio(16, 9, "Breitbild", small: (1024, 576), normal: nil, large: (1728, 960)),
        AspectRatio(9, 16, "Story", small: (576, 1024), normal: nil, large: (960, 1728)),
    ]

    static let square = all.first { $0.width == $0.height }!

    static func closest(to size: CGSize) -> AspectRatio {
        guard size.width > 0, size.height > 0 else { return square }
        return closest(toRatio: size.width / size.height)
    }

    static func closest(toRatio ratio: Double) -> AspectRatio {
        guard ratio > 0, ratio.isFinite else { return square }
        return all.min { $0.distance(to: ratio) < $1.distance(to: ratio) } ?? square
    }

    static func with(id: String) -> AspectRatio? {
        all.first { $0.id == id }
    }
}
