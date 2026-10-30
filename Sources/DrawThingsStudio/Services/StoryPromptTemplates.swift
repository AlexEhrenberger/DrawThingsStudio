import Foundation

/// Gemmas Anweisungen für Stories: erst die Handlung aus allen Bildern, dann je Übergang der Prompt fürs Videomodell.
extension PromptTemplates {

    // MARK: Handlung

    nonisolated static let storyArc = """
    You are the story editor of "DrawThings Studio". The user arranged still pictures in a fixed order – the first picture is the beginning, the last picture is the end – and wants to turn them into a short film: every two neighbouring pictures become one video clip that moves from the first picture to the second.
    You see the pictures attached in story order; the request lists the story number of every attached picture. With many pictures you only see an even sample – infer the missing moments briefly from their neighbours.

    Write in German, plain text without markdown:
    - "about": 2 to 4 sentences – what the story is about: who, where, the mood, and how it develops from the beginning to the end.
    - "pictures": exactly one entry per story picture, in story order (picture 1 first) – what happens at this moment of the story, in a few words, based on what you see. No numbering, the app adds it.
    Follow the user's idea if there is one. Describe only what the pictures support; do not invent names for people unless the user gave them.

    Answer with JSON only.
    """

    static func storyArcRequest(numbers: [Int], total: Int, idea: String) -> String {
        var parts = ["The story has \(total) pictures. Attached in this order: " + numbers.map { "story picture \($0)" }.joined(separator: ", ") + "."]
        parts.append(idea.isEmpty ? "The user gave no idea – find the story yourself." : "The user's idea (German): \"\(idea)\"")
        return parts.joined(separator: "\n")
    }

    /// Ein Eintrag je Bild der Story – die App nummeriert („Bild 3: …“), damit die Zeilen zu den Bildern passen.
    static func storyArcSchema(pictureCount: Int) -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "about": ["type": "string"],
                "pictures": ["type": "array", "items": ["type": "string"], "minItems": pictureCount, "maxItems": pictureCount],
            ],
            "required": ["about", "pictures"],
            "additionalProperties": false,
        ]
    }

    static func storyArcText(about: String, pictures: [String]) -> String {
        let lines = pictures.enumerated().map { "Bild \($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespacesAndNewlines))" }
        return ([about.trimmingCharacters(in: .whitespacesAndNewlines), ""] + lines).joined(separator: "\n")
    }

    // MARK: Clips – Gemini Omni

    /// Gemini Omni im Modus Start- und Endbild – nach Googles Prompt-Anleitung für Omni (siehe `VideoPreset.geminiOmni`).
    nonisolated static let geminiOmniClip = """
    You are the video prompt writer of "DrawThings Studio". The user turns a story of still pictures into a short film with Google's video model Gemini Omni. Each clip is generated in first-and-last-frame mode: Gemini Omni receives a FIRST FRAME and a LAST FRAME and animates the scene from the first picture to the second. You see both frames yourself: Picture 1 is the first frame, Picture 2 is the last frame. The clips are joined in story order, so the last frame of one clip is the first frame of the next.

    Write ONE prompt for this clip, following Google's prompting guidance for Gemini Omni:
    - Open on the first frame: name the main subject and the setting with a few concrete features you actually see (who, clothing, place, light).
    - Describe the motion as a short sequence of beats that fits the duration – what the subject does, how objects and the environment move, with physically believable timing. Natural timing such as "after two seconds" or timecodes like [0-3s] are fine.
    - Give the camera clearly: shot size (wide, medium, close-up) and one main movement – static / locked off, slow push in, pull back, dolly, pan, tilt, tracking, orbit, crane. Keep camera moves moderate; fast spins and orbits break the identity of people.
    - End on the last frame: state precisely what the final frame shows – subject position, pose, framing and light arrive exactly at Picture 2.
    - When the two frames differ strongly (another place, time of day, framing or outfit), invent a motivated transition inside the shot – the camera pushes through a doorway, passes behind a foreground object, whip pans, follows a moving element, or the light changes with time – instead of a hard cut.
    - Keep identity consistent: the same people keep face, hair, body and clothing unless the frames show a change. Say briefly what stays the same.
    - Lighting and look follow the two frames. Describe a change of light only if the frames show one. No quality or style buzzwords that compete with the frames ("cinematic masterpiece", "8k", "ultra-detailed", "photorealistic").
    - One continuous shot without cuts, unless the user asks for cuts.
    - Phrase constraints positively ("locked-off tripod shot", "the background stays still") instead of "don't …". Exclusions only as short statements such as "No dialogue."
    - No invented on-screen text, logos or brand names. Text only if the user asks for it, quoted exactly.
    - Dialogue only if the user's wish contains spoken words (in quotation marks) – it goes into "dialogue", not into "scene".
    - Write in English. Never write "Picture 1" or "Picture 2" – say "the first frame" and "the last frame" or describe the content.

    Fill the JSON fields:
    - "scene": the shot from the first frame to the last frame as ONE paragraph of 50 to 100 words – short, concrete, plain sentences. End it with "One continuous shot, no cuts." (unless the user asks for cuts). No markdown, no lists, no audio here.
    - "sound": the sound design only – ambience and sound effects that match the action, as a short comma-separated phrase, e.g. "soft wind, rustling fabric, distant church bells". Follow the audio instruction of the request.
    - "music": the music bed (style, mood, tempo) if the audio instruction asks for music, otherwise an empty string.
    - "dialogue": only if the user's wish contains spoken words: who says them and how, e.g. The man in black armor whispers: "Bleib bei mir." – the spoken words stay exactly as the user wrote them, in their original language. Otherwise an empty string.
    - "summary": in German, one short sentence – what happens in this clip, for the user's storyboard.

    Answer with JSON only.
    """

    struct ClipContext {
        let number: Int
        let total: Int
        let fromNumber: Int
        let toNumber: Int
        let duration: Int
        let format: StoryVideoFormat
        let audio: StoryAudio
        let idea: String
        let arc: String
        let previous: String?
        let next: String?
        let wish: String
    }

    static func clipRequest(_ context: ClipContext) -> String {
        var parts = [
            "Clip \(context.number) of \(context.total). Duration: \(context.duration) seconds. Aspect ratio: \(context.format.promptText).",
            "Attached: Picture 1 = FIRST FRAME (story picture \(context.fromNumber)). Picture 2 = LAST FRAME (story picture \(context.toNumber)).",
        ]
        if !context.idea.isEmpty { parts.append("What the story is about (German, from the user): \"\(context.idea)\"") }
        if !context.arc.isEmpty { parts.append("Story arc (German):\n\"\"\"\n\(context.arc)\n\"\"\"") }
        parts.append(context.previous.map { "Previous clip – it ends on this clip's first frame: \"\($0)\"" } ?? "This is the opening clip of the story.")
        parts.append(context.next.map { "Next clip – it starts on this clip's last frame: \"\($0)\"" } ?? "This is the final clip of the story.")
        parts.append(context.wish.isEmpty
            ? "The user's wish for this clip: (none – decide yourself what happens, based on the two frames and the story)."
            : "The user's wish for this clip (German): \"\(context.wish)\"")
        parts.append("Audio: " + audioInstruction(context.audio))
        return parts.joined(separator: "\n")
    }

    private static func audioInstruction(_ audio: StoryAudio) -> String {
        switch audio {
        case .ambience: "ambience and sound effects only – \"music\" stays empty."
        case .music: "ambience and sound effects in \"sound\", and a fitting music bed in \"music\"."
        case .auto: "choose what serves the story best – ambience and effects in \"sound\", music in \"music\" only if it helps the story (otherwise empty)."
        }
    }

    static let clipSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "scene": ["type": "string"],
            "sound": ["type": "string"],
            "music": ["type": "string"],
            "dialogue": ["type": "string"],
            "summary": ["type": "string"],
        ],
        "required": ["scene", "sound", "music", "dialogue", "summary"],
        "additionalProperties": false,
    ]

    /// Prompt für Gemini Omni aus Gemmas Teilen – die Form garantiert die App, nicht Gemma:
    /// Szene als ein Absatz (mit Dialog) und „One continuous shot, no cuts.“, darunter „Sound design: …“ und ggf. „Music: …“.
    /// Ohne Angaben erfindet Omni Musik und Sprache – deshalb stehen Ausschlüsse ausdrücklich da.
    static func assembleClipPrompt(scene: String, sound: String, music: String, dialogue: String, audio: StoryAudio, wish: String) -> String {
        func sentence(_ text: String) -> String {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let last = text.last, !".!?\"“”".contains(last) else { return text }
            return text + "."
        }
        let closing = "One continuous shot, no cuts."
        var paragraph = sentence(cleanVideoPrompt(scene).components(separatedBy: .newlines).joined(separator: " "))
        // Den Schlusssatz ans Ende nach dem Dialog – Gemma setzt ihn mal, mal nicht.
        if paragraph.lowercased().hasSuffix(closing.lowercased()) {
            paragraph = String(paragraph.dropLast(closing.count)).trimmingCharacters(in: .whitespaces)
        }
        let dialogue = dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dialogue.isEmpty { paragraph += " " + sentence(dialogue) }
        let lowered = paragraph.lowercased()
        let wantsCuts = wish.lowercased().contains("schnitt") || wish.lowercased().contains("cut")
        if !wantsCuts, !lowered.contains("continuous"), !lowered.contains("no cuts") {
            paragraph += " " + closing
        }
        // Gesprochenes steht im Wunsch in Anführungszeichen.
        let hasSpeech = !dialogue.isEmpty || wish.contains("\"") || wish.contains("„") || wish.contains("“")
        let music = audio == .ambience ? "" : sentence(music)
        var soundLine = "Sound design: " + sentence(sound.isEmpty ? "natural ambience that matches the scene" : sound)
        if music.isEmpty, !soundLine.lowercased().contains("music") { soundLine += " No music." }
        if !hasSpeech, !soundLine.lowercased().contains("dialogue") { soundLine += " No dialogue." }
        var lines = [paragraph, soundLine]
        if !music.isEmpty { lines.append("Music: " + music) }
        return lines.joined(separator: "\n")
    }

    /// Wie `LMStudioClient.clean`, aber die Zeilen bleiben: Absatz oben, Ton („Sound design:“, „Music:“) darunter.
    static func cleanVideoPrompt(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "</think>") { text = String(text[range.upperBound...]) }
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "```", with: "")
        var lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let first = lines.first {
            for prefix in ["Prompt:", "Video prompt:", "Final prompt:"] where first.hasPrefix(prefix) {
                lines[0] = String(first.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        text = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        if text.count > 2, text.first == "\"", text.last == "\"", !text.dropFirst().dropLast().contains("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
