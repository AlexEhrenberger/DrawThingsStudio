import SwiftUI

/// RGB-Histogramm des angezeigten Bildes – wie in Fotos.
struct HistogramView: View {
    @Environment(Studio.self) private var studio
    @State private var histogram: ImageTools.Histogram?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
            if let histogram {
                Canvas { context, size in
                    context.blendMode = .plusLighter
                    let channels: [([Double], Color)] = [
                        (histogram.red, Color(red: 1, green: 0.25, blue: 0.25)),
                        (histogram.green, Color(red: 0.3, green: 0.95, blue: 0.35)),
                        (histogram.blue, Color(red: 0.3, green: 0.5, blue: 1)),
                    ]
                    for (values, color) in channels {
                        context.fill(area(values, in: size), with: .color(color.opacity(0.6)))
                    }
                    context.blendMode = .normal
                    context.stroke(line(histogram.luminance, in: size), with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
        .task(id: studio.displayImage.map(ObjectIdentifier.init)) {
            guard let image = studio.displayImage else { return }
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            histogram = ImageTools.histogram(image)
        }
    }

    private func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * Double(index) / Double(values.count - 1), y: size.height * (1 - value))
        }
    }

    private func area(_ values: [Double], in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLines(points(values, in: size))
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func line(_ values: [Double], in size: CGSize) -> Path {
        var path = Path()
        path.addLines(points(values, in: size))
        return path
    }
}

/// Tonwertkurve mit fünf Stützpunkten (Schwarz, Tiefen, Mitten, Lichter, Weiß).
struct CurveEditor: View {
    @Binding var values: [Double]
    @State private var dragIndex: Int?

    private let labels = ["Schwarz", "Tiefen", "Mitten", "Lichter", "Weiß"]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                grid(size)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: 0))
                }
                .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                curve(size)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(dragIndex == index ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: 13, height: 13)
                        .position(point(index, in: size))
                        .help(labels[index])
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = dragIndex ?? nearestIndex(to: value.startLocation, in: size)
                        dragIndex = index
                        var updated = values
                        updated[index] = min(max(1 - value.location.y / size.height, 0), 1)
                        values = updated
                    }
                    .onEnded { _ in dragIndex = nil }
            )
        }
    }

    private func point(_ index: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * Double(index) / 4, y: size.height * (1 - values[index]))
    }

    private func nearestIndex(to location: CGPoint, in size: CGSize) -> Int {
        (0..<5).min { abs(point($0, in: size).x - location.x) < abs(point($1, in: size).x - location.x) } ?? 2
    }

    private func grid(_ size: CGSize) -> Path {
        Path { path in
            for step in 1..<4 {
                let x = size.width * Double(step) / 4
                let y = size.height * Double(step) / 4
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    /// Catmull-Rom-Spline durch die fünf Punkte – ähnlich wie Core Image die Kurve interpoliert.
    private func curve(_ size: CGSize) -> Path {
        let points = (0..<5).map { CGPoint(x: Double($0) / 4, y: values[$0]) }
        var path = Path()
        for segment in 0..<4 {
            let p0 = points[max(segment - 1, 0)], p1 = points[segment]
            let p2 = points[segment + 1], p3 = points[min(segment + 2, 4)]
            for step in 0...12 {
                let t = Double(step) / 12
                let t2 = t * t
                let t3 = t2 * t
                let a: Double = 2 * p1.y
                let b: Double = (p2.y - p0.y) * t
                let c: Double = (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                let d: Double = (3 * p1.y - p0.y - 3 * p2.y + p3.y) * t3
                let y = min(max(0.5 * (a + b + c + d), 0), 1)
                let x = p1.x + (p2.x - p1.x) * t
                let point = CGPoint(x: x * size.width, y: (1 - y) * size.height)
                if segment == 0 && step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }
}

/// Kleiner Spinner + Text, solange Vision rechnet.
struct VisionBusyLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
