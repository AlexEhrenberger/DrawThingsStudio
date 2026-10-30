import SwiftUI

/// Vorschaubild eines Galerie-Bildes – lädt im Hintergrund, bis dahin ein Platzhalter im richtigen Format.
/// Wechselt das Bild an derselben Stelle (Inspector, Lupe), zeigt die Ansicht sofort das neue.
struct GalleryThumbnail: View {
    let item: GalleryItem
    /// Große Kacheln: nach dem Vorschaubild die volle Auflösung laden, damit nichts verwaschen aussieht.
    var prefersFullImage = false
    @State private var loaded: (id: UUID, image: CGImage)?

    private var image: CGImage? {
        if let loaded, loaded.id == item.id { return loaded.image }
        if prefersFullImage, let full = GalleryImages.cachedImage(item) { return full }
        return GalleryImages.cachedThumbnail(item)
    }

    var body: some View {
        Group {
            if let image {
                CGImageView(image: image)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .aspectRatio(item.aspect, contentMode: .fit)
            }
        }
        .task(id: LoadKey(id: item.id, full: prefersFullImage)) {
            if let image = await GalleryImages.thumbnail(for: item) { loaded = (item.id, image) }
            if prefersFullImage, !item.isVideo, let image = await GalleryImages.image(for: item) { loaded = (item.id, image) }
        }
    }

    private struct LoadKey: Equatable {
        let id: UUID
        let full: Bool
    }
}

/// Kennzeichen für Videos im Raster: Symbol und Länge.
struct VideoBadge: View {
    let item: GalleryItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
            if let length = item.videoLength {
                Text(Format.duration(length))
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.6)))
        .padding(6)
    }
}

/// Großes Bild für Lupe und Vergleich: erst das Vorschaubild, dann die volle Auflösung.
struct GalleryFullImage: View {
    let item: GalleryItem
    var interpolation: Image.Interpolation = .high
    @State private var loaded: (id: UUID, image: CGImage)?

    private var image: CGImage? {
        if let loaded, loaded.id == item.id { return loaded.image }
        return GalleryImages.cachedImage(item) ?? GalleryImages.cachedThumbnail(item)
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(interpolation)
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .aspectRatio(item.aspect, contentMode: .fit)
            }
        }
        .task(id: item.id) {
            if let image = await GalleryImages.image(for: item) { loaded = (item.id, image) }
        }
    }
}

/// Behalten / Verwerfen – zwei kleine Knöpfe wie in Lightroom.
struct FlagButtons: View {
    let flag: GalleryFlag
    var size: CGFloat = 12
    let set: (GalleryFlag) -> Void

    var body: some View {
        HStack(spacing: size * 0.5) {
            Button { set(.pick) } label: {
                Image(systemName: flag == .pick ? "flag.fill" : "flag")
                    .foregroundStyle(flag == .pick ? Color.accentColor : Color.secondary)
            }
            .help(flag == .pick ? "Markierung entfernen (U)" : "Behalten (P)")
            Button { set(.reject) } label: {
                Image(systemName: flag == .reject ? "xmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(flag == .reject ? Color.red : Color.secondary)
            }
            .help(flag == .reject ? "Markierung entfernen (U)" : "Verwerfen (X)")
        }
        .font(.system(size: size, weight: .semibold))
        .buttonStyle(.plain)
    }
}

/// Fünf Sterne; ein Klick auf den aktuellen Wert setzt die Bewertung zurück.
struct StarRating: View {
    let rating: Int
    var size: CGFloat = 11
    /// Leere Sterne nur andeuten (im Raster), damit die Kachel ruhig bleibt.
    var subtleEmpty = false
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(1...5, id: \.self) { value in
                Button { set(value) } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? Color.yellow : Color.secondary.opacity(subtleEmpty ? 0.45 : 0.8))
                }
                .help("\(value) \(value == 1 ? "Stern" : "Sterne") (\(value))")
            }
        }
        .font(.system(size: size, weight: .medium))
        .buttonStyle(.plain)
    }
}

/// Hintergrund der Galerie – wie die Arbeitsfläche, aber ohne Punktraster.
struct GalleryBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark ? Color(white: 0.115) : Color(white: 0.9))
            .ignoresSafeArea()
    }
}

extension GalleryItem {
    /// Art des Bildes – Videos heißen „Video“, nicht „Importiert“.
    var kindTitle: String { isVideo ? "Video" : source.title }
    var kindSymbol: String { isVideo ? "video" : source.symbol }

    /// Kurzer Titel: Variante der Serie oder Art des Bildes.
    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let stackIndex { return "Bild \(stackIndex)" }
        return kindTitle
    }

    /// Titel neben der Nummer einer Serie – leer, wenn er nur die Nummer wiederholen würde.
    var captionTitle: String? {
        if let label, !label.isEmpty { return label }
        return stackIndex == nil ? kindTitle : nil
    }
}
