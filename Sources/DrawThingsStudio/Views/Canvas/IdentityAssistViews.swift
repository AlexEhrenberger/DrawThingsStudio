import SwiftUI

/// Oben auf dem Canvas im Modus „Bearbeiten“: Vorschlag, die Gesichtsreferenz zu nutzen – oder ihr Stand.
struct IdentityAssistBanner: View {
    @Environment(Studio.self) private var studio
    @State private var showPreview = false

    var body: some View {
        if studio.mode == .edit, studio.current != nil {
            if let (assist, persona) = studio.activeIdentityAssist {
                active(assist, persona: persona)
            } else if let persona = studio.identityCandidate, studio.identityAssist?.personaID != persona.id {
                suggestion(persona)
            }
        }
    }

    private func suggestion(_ persona: Persona) -> some View {
        let views = IdentityComposite.photos(of: persona).count
        return HStack(spacing: 10) {
            PersonaAvatar(persona: persona, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("„\(persona.name)“ ist auf dem Bild")
                    .font(.callout.weight(.semibold))
                Text(views > 1
                     ? "Für mehr Gesichtstreue Frontal- und Seitenansicht als Raster neben das Bild legen – hilft z. B., wenn sich der Kopf zur Kamera drehen soll."
                     : "Für mehr Gesichtstreue das Frontalfoto als Raster neben das Bild legen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Gesichtsreferenz nutzen", systemImage: "person.crop.rectangle.stack") {
                withAnimation(.smooth) { studio.enableIdentityAssist(persona.id) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            Button {
                withAnimation(.smooth) { studio.identityAssist = IdentityAssist(personaID: persona.id, isEnabled: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Nicht für dieses Bild – lässt sich links unter „Bearbeitung › Gesichtsreferenz“ wieder einschalten")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 660)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func active(_ assist: IdentityAssist, persona: Persona) -> some View {
        let warn = (assist.lastStripChange ?? 0) > IdentityAssist.driftWarning
        return HStack(spacing: 10) {
            PersonaAvatar(persona: persona, size: 22)
            Text("Gesichtsreferenz: \(persona.name)")
                .font(.callout.weight(.medium))
            Text("· " + IdentityComposite.photos(of: persona).map(\.view.title).joined(separator: " + "))
                .font(.callout)
                .foregroundStyle(.secondary)
            if warn {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Beim letzten Durchlauf hat Qwen das Raster verändert – Ergebnis prüfen")
            }
            Button("Raster", systemImage: "eye") { showPreview.toggle() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Zeigen, was an Draw Things geht – und was zuletzt zurückkam")
                .popover(isPresented: $showPreview, arrowEdge: .bottom) { IdentityAssistPreview(persona: persona) }
            Button {
                withAnimation(.smooth) { studio.disableIdentityAssist() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Gesichtsreferenz ausschalten")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Das Raster, das an Draw Things geht – und das ganze Ergebnis des letzten Durchlaufs.
struct IdentityAssistPreview: View {
    @Environment(Studio.self) private var studio
    let persona: Persona
    @State private var composite: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gesichtsreferenz")
                .font(.headline)
            Text("Links das Bild, das bearbeitet wird; rechts die Ansichten von \(persona.name). Draw Things bekommt alles als ein Bild in einer seiner Größen – das Bild darin ist deshalb kleiner als bei einer normalen Bearbeitung. Danach schneidet die App das große Feld wieder heraus.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                figure("Geht an Draw Things", image: composite)
                if let raw = studio.identityAssist?.lastRawOutput {
                    figure("Zuletzt zurück", image: raw)
                }
            }
            if let change = studio.identityAssist?.lastStripChange {
                Label(
                    change > IdentityAssist.driftWarning
                        ? "Die Referenzspalte hat sich um \(Int((change * 100).rounded())) % verändert – Qwen hat das Raster wohl nicht gehalten."
                        : "Die Referenzspalte blieb fast gleich (\(Int((change * 100).rounded())) %) – das Raster hat gehalten.",
                    systemImage: change > IdentityAssist.driftWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(change > IdentityAssist.driftWarning ? .orange : .green)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: studio.identityAssist?.lastRawOutput == nil ? 380 : 640)
        // Neu zusammensetzen, wenn sich Bild, Format oder Größe ändern.
        .task(id: "\(studio.currentID?.uuidString ?? "")|\(studio.targetSize(for: .edit).map(Format.size) ?? "")|\(studio.sizeTier.rawValue)") {
            guard let base = studio.current?.image, let size = studio.targetSize(for: .edit) else { return }
            composite = await IdentityComposite.render(base: ImageTools.filled(base, to: size), persona: persona, tier: studio.sizeTier)?.image
        }
    }

    private func figure(_ title: String, image: CGImage?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                if let image {
                    CGImageView(image: ImageTools.scaled(image, maxSide: 900))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    ProgressView()
                }
            }
            .frame(height: 230)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// In der Seitenleiste unter „Bearbeitung“: Gesichtsreferenz für jedes Bild ein- und ausschalten.
struct IdentityAssistRow: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let personas = studio.personas.personas.filter { $0.mainPhoto != nil }
        if !personas.isEmpty {
            let active = studio.activeIdentityAssist?.persona
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .foregroundStyle(active == nil ? Color.secondary : Color.accentColor)
                        .frame(width: 18)
                    Text("Gesichtsreferenz")
                    Spacer(minLength: 6)
                    Menu {
                        ForEach(personas) { persona in
                            Button {
                                studio.enableIdentityAssist(persona.id)
                            } label: {
                                Label(persona.name, systemImage: active?.id == persona.id ? "checkmark" : "person.crop.square")
                            }
                        }
                        if active != nil {
                            Divider()
                            Button("Aus", systemImage: "xmark") { studio.disableIdentityAssist() }
                        }
                    } label: {
                        Text(active?.name ?? "Aus")
                    }
                    .menuStyle(.button)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(studio.current == nil)
                }
                Text("Legt Frontal- und Seitenansicht des Charakters als Raster neben das Bild – für mehr Gesichtstreue, z. B. wenn sich der Kopf drehen soll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
}
