import AppKit
import SwiftUI

/// Vorher/Nachher-Vergleich: „Nachher“ liegt unten, „Vorher“ ist links der Trennlinie darübergelegt.
/// Ziehen (oder Klicken) irgendwo im Bild verschiebt die Linie.
struct CompareSplitView: View {
    let before: CGImage
    let after: CGImage
    let size: CGSize
    @Binding var position: Double

    @State private var isDragging = false

    var body: some View {
        let x = size.width * min(max(position, 0), 1)
        ZStack(alignment: .topLeading) {
            layer(after)
            layer(before)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: x)
                }

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: size.height)
                .shadow(color: .black.opacity(0.45), radius: 3)
                .position(x: x, y: size.height / 2)

            Circle()
                .fill(.white)
                .frame(width: isDragging ? 40 : 34, height: isDragging ? 40 : 34)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                }
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                .position(x: x, y: size.height / 2)
                .animation(.easeOut(duration: 0.12), value: isDragging)

            tag("Vorher")
                .opacity(x > 110 ? 1 : 0)
                .position(x: 52, y: 26)
            tag("Nachher")
                .opacity(x < size.width - 110 ? 1 : 0)
                .position(x: size.width - 56, y: 26)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    position = min(max(value.location.x / size.width, 0), 1)
                }
                .onEnded { _ in isDragging = false }
        )
        .pointerStyle(.columnResize)
        .animation(.easeOut(duration: 0.15), value: x > 110)
        .animation(.easeOut(duration: 0.15), value: x < size.width - 110)
    }

    private func layer(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
    }
}
