import SwiftUI

// MARK: - Zuschnittrahmen

/// Rahmen mit Griffen direkt auf dem Bild. Arbeitet in normierten Koordinaten.
struct CropOverlay: View {
    @Environment(Studio.self) private var studio
    let size: CGSize
    @State private var startRect: CGRect?

    enum Handle: CaseIterable {
        case move, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        func position(in frame: CGRect) -> CGPoint {
            switch self {
            case .move: CGPoint(x: frame.midX, y: frame.midY)
            case .topLeft: CGPoint(x: frame.minX, y: frame.minY)
            case .top: CGPoint(x: frame.midX, y: frame.minY)
            case .topRight: CGPoint(x: frame.maxX, y: frame.minY)
            case .right: CGPoint(x: frame.maxX, y: frame.midY)
            case .bottomRight: CGPoint(x: frame.maxX, y: frame.maxY)
            case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
            case .bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
            case .left: CGPoint(x: frame.minX, y: frame.midY)
            }
        }

        var isCorner: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(self) }
    }

    var body: some View {
        let rect = studio.crop.rect
        let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        ZStack {
            // Außerhalb abdunkeln
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // Drittel-Raster
            Path { path in
                for step in 1...2 {
                    let x = frame.minX + frame.width * Double(step) / 3
                    let y = frame.minY + frame.height * Double(step) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY))
                    path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y))
                    path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 0.7)
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)

            // Mitte verschieben
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(frame.width - 30, 1), height: max(frame.height - 30, 1))
                .position(x: frame.midX, y: frame.midY)
                .gesture(drag(.move))

            ForEach(Handle.allCases.filter { $0 != .move }, id: \.self) { handle in
                handleView(handle)
                    .position(handle.position(in: frame))
                    .gesture(drag(handle))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func handleView(_ handle: Handle) -> some View {
        if handle.isCorner {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        } else {
            Capsule()
                .fill(Color.white)
                .frame(width: handle == .top || handle == .bottom ? 24 : 5, height: handle == .top || handle == .bottom ? 5 : 24)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
    }

    private func drag(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = startRect ?? studio.crop.rect
                if startRect == nil { startRect = start }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                var ratio: Double?
                if let locked = studio.crop.lockedRatio, let image = studio.current?.image {
                    ratio = locked * Double(image.height) / Double(image.width)
                }
                studio.crop.rect = Self.adjust(start, handle: handle, dx: dx, dy: dy, ratio: ratio)
            }
            .onEnded { _ in startRect = nil }
    }

    /// Neuer Rahmen nach dem Ziehen eines Griffs; `ratio` = Breite/Höhe in normierten Einheiten.
    static func adjust(_ start: CGRect, handle: Handle, dx: Double, dy: Double, ratio: Double?) -> CGRect {
        let minSize = 0.05
        if handle == .move {
            return CGRect(
                x: min(max(start.minX + dx, 0), 1 - start.width),
                y: min(max(start.minY + dy, 0), 1 - start.height),
                width: start.width, height: start.height
            )
        }
        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        switch handle {
        case .topLeft: minX += dx; minY += dy
        case .top: minY += dy
        case .topRight: maxX += dx; minY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; maxY += dy
        case .bottom: maxY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .left: minX += dx
        case .move: break
        }
        minX = min(max(minX, 0), maxX - minSize)
        maxX = max(min(maxX, 1), minX + minSize)
        minY = min(max(minY, 0), maxY - minSize)
        maxY = max(min(maxY, 1), minY + minSize)
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        guard let ratio else { return rect }
        switch handle {
        case .left, .right:
            let height = rect.width / ratio
            rect = CGRect(x: rect.minX, y: start.midY - height / 2, width: rect.width, height: height)
        case .top, .bottom:
            let width = rect.height * ratio
            rect = CGRect(x: start.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        default:
            // Ecken: Breite bestimmt die Höhe, die gegenüberliegende Ecke bleibt stehen.
            let width = rect.width
            let height = width / ratio
            switch handle {
            case .topLeft: rect = CGRect(x: start.maxX - width, y: start.maxY - height, width: width, height: height)
            case .topRight: rect = CGRect(x: start.minX, y: start.maxY - height, width: width, height: height)
            case .bottomLeft: rect = CGRect(x: start.maxX - width, y: start.minY, width: width, height: height)
            default: rect = CGRect(x: start.minX, y: start.minY, width: width, height: height)
            }
        }
        let epsilon = 0.0001
        guard rect.minX >= -epsilon, rect.minY >= -epsilon, rect.maxX <= 1 + epsilon, rect.maxY <= 1 + epsilon,
              rect.width >= minSize, rect.height >= minSize else { return start }
        return rect
    }
}

// MARK: - Pinsel

/// Malen und Radieren der Auswahl. Zeigt den Pinsel als Kreis unter dem Mauszeiger.
struct BrushOverlay: View {
    @Environment(Studio.self) private var studio
    let size: CGSize
    let erase: Bool
    @State private var stroke: [CGPoint] = []
    @State private var hover: CGPoint?

    var body: some View {
        let diameter = studio.brushDiameter * max(size.width, size.height)
        Canvas { context, _ in
            if !stroke.isEmpty {
                var path = Path()
                if stroke.count == 1 {
                    let point = stroke[0]
                    path.addEllipse(in: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter))
                    context.fill(path, with: .color(strokeColor))
                } else {
                    path.addLines(stroke)
                    context.stroke(path, with: .color(strokeColor), style: StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))
                }
            }
            if let hover {
                let ring = Path(ellipseIn: CGRect(x: hover.x - diameter / 2, y: hover.y - diameter / 2, width: diameter, height: diameter))
                context.stroke(ring, with: .color(.black.opacity(0.6)), lineWidth: 3)
                context.stroke(ring, with: .color(.white), lineWidth: 1.2)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hover = location
            case .ended: hover = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    stroke.append(value.location)
                    hover = value.location
                }
                .onEnded { _ in
                    let points = stroke.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
                    stroke = []
                    studio.paintSelection(points, erase: erase)
                }
        )
    }

    private var strokeColor: Color {
        erase ? Color.white.opacity(0.45) : Color.accentColor.opacity(0.5)
    }
}

// MARK: - Pipette

struct PipetteOverlay: View {
    @Environment(Studio.self) private var studio
    let size: CGSize

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                studio.pickWhiteBalance(at: CGPoint(x: location.x / size.width, y: location.y / size.height))
            }
            .pointerStyle(.rectSelection)
    }
}
