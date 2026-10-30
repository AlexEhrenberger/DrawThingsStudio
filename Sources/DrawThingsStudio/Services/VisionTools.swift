import CoreGraphics
import CoreImage
import Vision

/// Apples Bildanalyse (Vision) – läuft lokal, ohne Gemma und ohne Draw Things.
enum VisionTools {

    /// Maske des Hauptmotivs (wie „Motiv anheben“ in Fotos) oder nur der Personen.
    static func subjectMask(for image: CGImage, peopleOnly: Bool) async throws -> CGImage? {
        let handler = ImageRequestHandler(image)
        let observation: InstanceMaskObservation?
        if peopleOnly {
            observation = try await handler.perform(GeneratePersonInstanceMaskRequest())
        } else {
            observation = try await handler.perform(GenerateForegroundInstanceMaskRequest())
        }
        guard let observation, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateScaledMask(for: observation.allInstances, scaledToImageFrom: handler)
        return ImageTools.grayImage(CIImage(cvPixelBuffer: buffer), size: CGSize(width: image.width, height: image.height))
    }

    /// Neigung des Horizonts in Grad (positiv = gegen den Uhrzeigersinn geneigt).
    static func horizonAngle(of image: CGImage) async throws -> Double? {
        guard let observation = try await DetectHorizonRequest().perform(on: image) else { return nil }
        return observation.angle.converted(to: .degrees).value
    }

    /// Bereich, auf den das Auge zuerst fällt – normiert, Ursprung oben links.
    static func salientRect(of image: CGImage) async throws -> CGRect? {
        let observation = try await GenerateAttentionBasedSaliencyImageRequest().perform(on: image)
        let boxes = observation.salientObjects.map { object -> CGRect in
            let box = object.boundingBox
            // Vision zählt von unten links.
            return CGRect(x: box.origin.x, y: 1 - box.origin.y - box.height, width: box.width, height: box.height)
        }
        guard var union = boxes.first else { return nil }
        for box in boxes.dropFirst() { union = union.union(box) }
        return union
    }

    /// Größtes Gesicht im Bild: Rahmen (normiert, Ursprung oben links) und Kopfdrehung in Grad
    /// (negativ = zum linken Bildrand gedreht).
    static func mainFace(in image: CGImage) async throws -> (rect: CGRect, yaw: Double)? {
        let faces = try await DetectFaceRectanglesRequest().perform(on: image)
        guard let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else { return nil }
        let box = face.boundingBox
        let rect = CGRect(x: box.origin.x, y: 1 - box.origin.y - box.height, width: box.width, height: box.height)
        return (rect, face.yaw.converted(to: .degrees).value)
    }

    /// Erkannte Textzeilen, von oben nach unten.
    static func recognizeText(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: image)
        return observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
