import AppKit
import SwiftUI

/// Präsentation einer Story wie eine Diashow: schwarz, ein Bild oder ein Raster aus 2 bzw. 4 Bildern je Seite,
/// vom Anfang bis zum Ende. Im Vollbild oder im Fenster – umschaltbar mit F.
/// → / Leertaste / Klick blättert weiter, ← zurück, 1 · 2 · 4 wechselt das Raster, Esc beendet.
/// Die Leiste unten verschwindet, solange die Maus ruht.
struct StoryPresentationView: View {
    @Environment(Studio.self) private var studio
    let presentation: StoryPresentation

    @FocusState private var isFocused: Bool
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let gallery = studio.gallery
        let items = gallery.storyItems(presentation.storyID)
        let perPage = presentation.layout.rawValue
        let isEnd = presentation.index >= items.count
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if items.isEmpty || isEnd {
                    endScreen(isEmpty: items.isEmpty)
                } else {
                    page(Array(items[presentation.index..<min(presentation.index + perPage, items.count)]),
                         firstNumber: presentation.index + 1)
                }
            }
            .id(PageKey(index: presentation.index, layout: presentation.layout))
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: PageKey(index: presentation.index, layout: presentation.layout))
        .contentShape(Rectangle())
        .onTapGesture { studio.stepPresentation(1) }
        .overlay(alignment: .top) {
            if let story = gallery.story(presentation.storyID) {
                Text(story.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.clear, in: .capsule)
                    .padding(.top, presentation.isFullScreen ? 16 : 10)
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            controls(count: items.count, isEnd: isEnd)
                .padding(.bottom, 22)
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
        }
        .animation(.easeOut(duration: 0.25), value: chromeVisible)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
        .onContinuousHover { phase in
            if case .active = phase { revealChrome() }
        }
        .onAppear {
            isFocused = true
            revealChrome()
        }
        .onDisappear {
            hideTask?.cancel()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        // Nächste Seite schon laden, damit beim Blättern nichts nachzeichnet.
        .task(id: presentation.index) {
            let next = items.dropFirst(presentation.index + perPage).prefix(perPage)
            for item in next { _ = await GalleryImages.image(for: item) }
        }
    }

    private struct PageKey: Hashable {
        let index: Int
        let layout: PresentationLayout
    }

    // MARK: Seite

    @ViewBuilder
    private func page(_ items: [GalleryItem], firstNumber: Int) -> some View {
        let gap: CGFloat = presentation.layout == .single ? 0 : 14
        let inset: CGFloat = presentation.layout == .single ? (presentation.isFullScreen ? 0 : 12) : 24
        switch presentation.layout {
        case .single:
            frame(items[0], number: firstNumber, alignment: .center)
                .padding(inset)
        case .two:
            HStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { slot in
                    cell(items, slot: slot, firstNumber: firstNumber)
                }
            }
            .padding(inset)
        case .four:
            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { column in
                            cell(items, slot: row * 2 + column, firstNumber: firstNumber)
                        }
                    }
                }
            }
            .padding(inset)
        }
    }

    /// Platz im Raster – auf der letzten Seite bleiben übrige Plätze leer, damit nichts springt.
    /// Die Bilder rücken zur Mitte zusammen, statt mitten in ihrer Zelle zu stehen.
    @ViewBuilder
    private func cell(_ items: [GalleryItem], slot: Int, firstNumber: Int) -> some View {
        if items.indices.contains(slot) {
            let alignment: Alignment = switch (presentation.layout, slot) {
            case (.two, 0): .trailing
            case (.two, _): .leading
            case (.four, 0): .bottomTrailing
            case (.four, 1): .bottomLeading
            case (.four, 2): .topTrailing
            default: .topLeading
            }
            frame(items[slot], number: firstNumber + slot, alignment: alignment)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func frame(_ item: GalleryItem, number: Int, alignment: Alignment) -> some View {
        GalleryFullImage(item: item)
            .overlay(alignment: .bottomLeading) {
                if presentation.layout != .single {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(8)
                        .opacity(chromeVisible ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func endScreen(isEmpty: Bool) -> some View {
        VStack(spacing: 10) {
            Text(isEmpty ? "Die Story ist leer" : "Ende der Story")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(isEmpty ? "Esc beendet" : "← zurück · Esc beendet")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Leiste

    private func controls(count: Int, isEnd: Bool) -> some View {
        let perPage = presentation.layout.rawValue
        let shownFirst = min(presentation.index + 1, count)
        let shownLast = min(presentation.index + perPage, count)
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    chromeButton("chevron.left", help: "Zurück (←)") { studio.stepPresentation(-1) }
                        .disabled(presentation.index == 0)
                    Text(isEnd ? "Ende" : shownFirst == shownLast ? "\(shownFirst) / \(count)" : "\(shownFirst)–\(shownLast) / \(count)")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(minWidth: 74)
                    chromeButton("chevron.right", help: "Weiter (→, Leertaste, Klick)") { studio.stepPresentation(1) }
                        .disabled(isEnd)
                }
                .padding(.horizontal, 6)
                .glassEffect(.clear, in: .capsule)

                HStack(spacing: 2) {
                    ForEach(PresentationLayout.allCases) { layout in
                        chromeButton(layout.symbol, isOn: presentation.layout == layout, help: "\(layout.title) (\(layout.rawValue))") {
                            studio.setPresentationLayout(layout)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .glassEffect(.clear, in: .capsule)

                HStack(spacing: 2) {
                    chromeButton(presentation.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 help: presentation.isFullScreen ? "Im Fenster präsentieren (F)" : "Im Vollbild präsentieren (F)") {
                        studio.setPresentationFullScreen(!presentation.isFullScreen)
                    }
                    chromeButton("xmark", help: "Präsentation beenden (Esc)") { studio.endPresentation() }
                }
                .padding(.horizontal, 6)
                .glassEffect(.clear, in: .capsule)
            }
        }
    }

    private func chromeButton(_ symbol: String, isOn: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : .white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Tastatur & Maus

    /// Tasten zeigen die Leiste nicht – beim Vortrag soll nur das Bild stehen.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .rightArrow, .downArrow, .space, .return, .pageDown:
            studio.stepPresentation(1)
            return .handled
        case .leftArrow, .upArrow, .pageUp, .delete:
            studio.stepPresentation(-1)
            return .handled
        case .home:
            studio.jumpPresentation(toEnd: false)
            return .handled
        case .end:
            studio.jumpPresentation(toEnd: true)
            return .handled
        case .escape:
            studio.endPresentation()
            return .handled
        default:
            break
        }
        guard !press.modifiers.contains(.command) else { return .ignored }
        switch press.characters.lowercased() {
        case "1": studio.setPresentationLayout(.single)
        case "2": studio.setPresentationLayout(.two)
        case "4": studio.setPresentationLayout(.four)
        case "f": studio.setPresentationFullScreen(!presentation.isFullScreen)
        default: return .ignored
        }
        return .handled
    }

    /// Leiste zeigen und nach 2,5 s Ruhe wieder ausblenden – samt Mauszeiger.
    private func revealChrome() {
        if !chromeVisible { chromeVisible = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            chromeVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}
