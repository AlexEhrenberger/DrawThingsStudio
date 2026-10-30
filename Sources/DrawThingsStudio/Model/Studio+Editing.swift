import AppKit

/// Klassische Bildbearbeitung mit Apples Frameworks: Zuschnitt, Begradigung,
/// Auswahl (Vision + Pinsel), Hintergrund-Effekte, Weißabgleich, Hochskalieren.
extension Studio {

    /// Welches Werkzeug Mausaktionen auf dem Canvas bekommt.
    var canvasTool: CanvasTool {
        guard current != nil, !isGenerating, !isComparing else { return .none }
        if isPickingWhiteBalance { return .pipette }
        if isSplitComparing, comparisonPair != nil { return .compare }
        switch inspectorTab {
        case .crop: return .crop
        case .selection:
            switch selectionTool {
            case .brush: return .brush
            case .eraser: return .eraser
            case .hand: return .none
            }
        default: return .none
        }
    }

    // MARK: Zuschneiden

    func scheduleCropPreview() {
        cropPreviewTask?.cancel()
        guard let base = previewBase, crop.angle != 0 else {
            cropPreview = nil
            return
        }
        let angle = crop.angle
        cropPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(15))
            guard !Task.isCancelled else { return }
            let preview = ImageTools.straightened(base, degrees: angle)
            guard !Task.isCancelled else { return }
            cropPreview = preview
        }
    }

    /// Feste Seitenverhältnisse: größtmöglicher Ausschnitt, mittig.
    func setCropRatio(_ id: String, ratio: Double?) {
        guard let image = current?.image else { return }
        crop.ratioID = id
        crop.lockedRatio = ratio
        guard let ratio else { return }
        crop.rect = Self.largestRect(ratio: ratio, imageSize: CGSize(width: image.width, height: image.height), around: CGPoint(x: crop.rect.midX, y: crop.rect.midY))
    }

    /// Größter Ausschnitt mit Seitenverhältnis `ratio` (Pixel), möglichst um `center`.
    static func largestRect(ratio: Double, imageSize: CGSize, around center: CGPoint) -> CGRect {
        let normalized = ratio * imageSize.height / imageSize.width
        var width = 1.0
        var height = 1.0
        if normalized >= 1 { height = 1 / normalized } else { width = normalized }
        let x = min(max(center.x - width / 2, 0), 1 - width)
        let y = min(max(center.y - height / 2, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func resetCrop() {
        crop = CropState()
    }

    func applyCrop() {
        guard let current, !crop.isIdentity else { return }
        var image = ImageTools.straightened(current.image, degrees: crop.angle)
        if crop.rect != CGRect(x: 0, y: 0, width: 1, height: 1) {
            image = ImageTools.cropped(image, normalized: crop.rect)
        }
        addVersion(ImageVersion(image: image, prompt: current.prompt, source: .transformed, parentID: current.id))
    }

    func autoStraighten() {
        guard let image = previewBase else { return }
        visionTask = .horizon
        Task {
            defer { visionTask = nil }
            do {
                if let angle = try await VisionTools.horizonAngle(of: image), abs(angle) > 0.05 {
                    crop.angle = (-angle * 10).rounded() / 10
                } else {
                    errorMessage = "Vision hat keinen schiefen Horizont gefunden."
                }
            } catch {
                errorMessage = "Horizont-Erkennung fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    /// Zuschnitt auf den Bereich, den Vision für den wichtigsten hält.
    func smartCrop() {
        guard let image = previewBase, let current else { return }
        visionTask = .saliency
        Task {
            defer { visionTask = nil }
            do {
                guard let salient = try await VisionTools.salientRect(of: image) else {
                    errorMessage = "Vision hat keinen klaren Bildschwerpunkt gefunden."
                    return
                }
                let size = CGSize(width: current.image.width, height: current.image.height)
                let ratio = crop.lockedRatio ?? aspect?.value ?? size.width / size.height
                var rect = Self.largestRect(ratio: ratio, imageSize: size, around: CGPoint(x: salient.midX, y: salient.midY))
                // Wenn der Schwerpunkt viel kleiner ist, enger um ihn herum schneiden.
                let margin = 1.35
                let needed = max(salient.width * margin / rect.width, salient.height * margin / rect.height)
                if needed < 1 {
                    let factor = max(needed, 0.45)
                    let width = rect.width * factor
                    let height = rect.height * factor
                    rect = CGRect(
                        x: min(max(salient.midX - width / 2, 0), 1 - width),
                        y: min(max(salient.midY - height / 2, 0), 1 - height),
                        width: width, height: height
                    )
                }
                crop.rect = rect
                if crop.lockedRatio == nil { crop.lockedRatio = ratio; crop.ratioID = "smart" }
            } catch {
                errorMessage = "Motiv-Zuschnitt fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func upscale() {
        guard let current else { return }
        let factor = max(current.image.width, current.image.height) > 3000 ? 1.5 : 2
        let image = ImageTools.upscaled(current.image, factor: factor)
        addVersion(ImageVersion(image: image, prompt: current.prompt, source: .transformed, parentID: current.id))
    }

    // MARK: Auswahl

    var hasSelection: Bool { selectionMask != nil }

    func selectSubject(peopleOnly: Bool) {
        guard let image = previewBase else { return }
        visionTask = peopleOnly ? .people : .subject
        Task {
            defer { visionTask = nil }
            do {
                if let mask = try await VisionTools.subjectMask(for: image, peopleOnly: peopleOnly) {
                    selectionMask = mask
                    selectionSource = peopleOnly ? .people : .subject
                } else {
                    errorMessage = peopleOnly ? "Vision hat keine Personen gefunden." : "Vision hat kein klares Hauptmotiv gefunden."
                }
            } catch {
                errorMessage = "Auswahl fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func invertSelection() {
        guard let mask = selectionMask else { return }
        selectionMask = ImageTools.inverted(mask)
        selectionSource = switch selectionSource {
        case .subject, .people: .inverted
        case .inverted: .subject
        case .painted: .painted
        }
    }

    func clearSelection() {
        selectionMask = nil
    }

    /// Pinselstrich übernehmen (Punkte normiert, Ursprung oben links).
    func paintSelection(_ points: [CGPoint], erase: Bool) {
        guard let base = previewBase, !points.isEmpty else { return }
        let mask = selectionMask ?? ImageTools.blankMask(width: base.width, height: base.height)
        guard let mask else { return }
        let painted = ImageTools.paint(mask, stroke: points, diameter: brushDiameter, erase: erase)
        if erase && ImageTools.isEmptyMask(painted) {
            selectionMask = nil
        } else {
            selectionMask = painted
            if selectionSource != .painted && !erase { selectionSource = .painted }
        }
    }

    func applyBackground(_ effect: ImageTools.BackgroundEffect) {
        guard let current, let mask = selectionMask else { return }
        let image = ImageTools.applyBackground(effect, to: current.image, mask: mask, feather: selectionFeather)
        addVersion(ImageVersion(image: image, prompt: current.prompt, source: .adjusted, parentID: current.id))
    }

    // MARK: Weißabgleich

    /// Klick mit der Pipette auf eine Stelle, die neutral grau sein soll.
    func pickWhiteBalance(at point: CGPoint) {
        isPickingWhiteBalance = false
        guard let image = previewBase, let color = ImageTools.averageColor(in: image, at: point) else { return }
        let average = (color.r + color.g + color.b) / 3
        guard average > 0.02, color.r > 0.01, color.g > 0.01, color.b > 0.01 else {
            errorMessage = "Diese Stelle ist zu dunkel für den Weißabgleich."
            return
        }
        adjustments.whiteBalance = [average / color.r, average / color.g, average / color.b].map { min(max($0, 0.5), 2) }
    }
}
