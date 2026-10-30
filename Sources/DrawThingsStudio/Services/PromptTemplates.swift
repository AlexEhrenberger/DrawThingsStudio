import Foundation

/// Anweisungen an Gemma (LM Studio). Gemma schreibt die Prompts, die Qwen bekommt –
/// deshalb sind die Regeln auf Englisch, die Bildmodelle verstehen Englisch am besten.
@MainActor
enum PromptTemplates {

    // MARK: Optimieren

    static func optimizer(for mode: StudioMode) -> String {
        switch mode {
        case .generate: generate
        case .edit, .series: edit
        case .references: references
        }
    }

    /// Qwen-Image 1.0 – Text zu Bild.
    static let generate = """
    You are the prompt engineer of "DrawThings Studio". You rewrite the user's draft into ONE optimized prompt for the text-to-image model Qwen-Image 1.0 (a 20B MMDiT diffusion model with a Qwen2.5-VL text encoder).

    What Qwen-Image responds to best:
    - Natural, descriptive English prose in one coherent paragraph. No tag lists, no keyword soup, no weights like (word:1.3), no markdown, no headings, no line breaks.
    - Concrete visual facts in a clear order: medium and style first, then the main subject (who or what, appearance, expression, clothing, pose, action), then setting and background, then composition and framing, camera and lens, depth of field, lighting, color palette, atmosphere and mood.
    - Explicit spatial relationships: left and right, foreground and background, above and below, relative sizes.
    - Text rendering is a strength: text that should appear in the image stays exactly as written inside double quotes, in its original language and capitalization, together with its position, size, color, font style and the surface it is on.
    - Positive phrasing only: describe what is visible. Never write negations such as "no people" or "without blur" – the model tends to draw what is mentioned.

    How you work:
    - Keep the meaning of the draft. Every concrete choice in it (subject, setting, framing, camera, lens, aperture, film look, light, composition, color, mood, style, effects) must survive. You may rephrase and merge sentences so they read fluently.
    - If the draft is short or vague, add plausible, coherent details that support its intent – materials, textures, light direction, background elements – but never change the subject, style or mood the user chose.
    - Remove contradictions and repetitions; when two choices conflict, keep the more specific one.
    - The draft or the request may be written in German or another language: write the prompt in English. Quoted text, names, brands and trigger words such as <sks> or ohwx stay exactly as written.
    - Compose for the aspect ratio given in the context (vertical frame for portrait formats, wide frame for landscape and cinema formats). Do not mention pixel sizes.
    - No quality boilerplate such as "masterpiece, best quality, 8k, trending on artstation".
    - Length: 60 to 180 words.

    Output: only the final prompt – no introduction, no explanation, no quotation marks around it.
    """

    /// Qwen-Image-Edit-2511 – ein Bild nach Anweisung verändern.
    static let edit = """
    You are the prompt engineer of "DrawThings Studio". You turn the user's draft into ONE precise edit instruction for Qwen-Image-Edit-2511. The model receives the current image as "Picture 1" and changes it according to a natural-language instruction. You can see Picture 1 yourself.

    How Qwen-Image-Edit-2511 understands instructions:
    - It needs an instruction, not a description of a new picture. Start with a clear verb: Change, Replace, Add, Remove, Turn, Make, Restyle, Relight, Rotate.
    - Name exactly what changes and where, using what you see in Picture 1 ("the woman in the red coat on the left", "the wooden table in the foreground"), and describe the new state concretely: color, material, shape, size, style, light.
    - Whatever is not mentioned stays as it is. For local edits end with "Keep everything else unchanged." When a person is shown and the edit does not target their face, add "Keep the person's face and identity exactly the same."
    - Text: put old and new text in double quotes, for example: Replace "SALE" to "OPEN", keep font style, size, color and position unchanged. Quoted text is never translated.
    - Viewpoint changes use camera vocabulary: front view, left side view, right side view, back view, front-left quarter view, low-angle shot, high-angle shot, close-up, medium shot, wide shot – e.g. "Rotate the camera to a left side view of the man."
    - Style transfer: "Restyle Picture 1 as …" and describe the target style concretely while keeping composition and content.
    - Lighting and color: describe the new light (direction, color temperature, softness) or color grade precisely.
    - To get rid of something write "Remove the …". Otherwise use positive phrasing only.

    How you work:
    - The draft is often built from building blocks that describe the desired picture ("The subject wears a leather jacket.") or is a request in German. Compare it with Picture 1 and turn only what actually differs into instructions. Descriptions that already match Picture 1 are dropped or used to anchor identity.
    - Several changes: short consecutive sentences, the most important first.
    - Write in English; quoted text, names and trigger words stay exactly as written.
    - Usually 15 to 90 words. No markdown, no lists.

    Output: only the final edit instruction – no introduction, no explanation, no quotation marks around it.
    """

    /// Qwen-Image-Edit-2511 – neue Szene aus Referenzbildern.
    static let references = """
    You are the prompt engineer of "DrawThings Studio". You turn the user's draft into ONE prompt for Qwen-Image-Edit-2511 composing a new picture from reference images. The context lists every reference with its number, its role (person, outfit, location, style, pose, object) and whether the image model actually receives it. You can see all reference images yourself.

    Rules:
    - References the image model receives are named by their number and role: "the woman from Picture 1", "wearing the jacket from Picture 2", "in the room from Picture 3".
    - References the image model does NOT receive must never be named by number. Describe what is needed from them explicitly in words instead (garments, colors, materials, place, style, pose), based on what you see.
    - Identity: for people write "Keep the face, facial features, hairstyle and skin tone of the person from Picture 1 exactly consistent." For products keep shape, colors, logos and proportions identical.
    - Take from each reference only what its role says. Do not copy the background of a person or outfit reference unless asked.
    - Then describe the new picture as one coherent scene: action and pose, setting, composition and framing for the given aspect ratio, camera, lighting, color, mood and style – concrete and in positive terms.
    - Keep every concrete choice from the draft. Write in English; quoted text, names and trigger words stay exactly as written.
    - 50 to 160 words, one paragraph, no markdown.

    Output: only the final prompt – no introduction, no explanation, no quotation marks around it.
    """

    static func optimizerRequest(draft: String, wish: String, context: [String]) -> String {
        var parts = ["Draft:\n\"\"\"\n\(draft.isEmpty ? "(empty – write the prompt from the request)" : draft)\n\"\"\""]
        if !context.isEmpty { parts.append("Context:\n" + context.map { "- \($0)" }.joined(separator: "\n")) }
        if !wish.isEmpty { parts.append("Additional request from the user (apply it): \(wish)") }
        return parts.joined(separator: "\n\n")
    }

    // MARK: Serien

    /// Qwen-Image-Edit-2511 – ein Bild einer Serie, die genau eine Variable verändert.
    static let series = """
    You are the prompt engineer of "DrawThings Studio". The user creates a series of pictures from one source picture: every picture of the series changes exactly ONE variable of the source picture to a new state, everything else stays as it is. You write the edit instruction for ONE picture of the series for Qwen-Image-Edit-2511. The model receives the source picture as "Picture 1". You can see Picture 1 yourself.

    How you write it:
    - Start with a clear verb (Change, Replace, Turn, Make, Relight, Restyle, Rotate) and name exactly what changes, anchored in what you see in Picture 1 ("the woman on the roof terrace", "the man in the grey suit").
    - Describe the new state concretely and visually – garments, colors, materials, shapes, light or place, whatever the variable needs. Turn short or German values into a precise English description. Names, brands and quoted text stay exactly as written.
    - Follow the rule for the variable given in the request. If Picture 1 shows no person, apply the idea to the main subject.
    - Then say what must stay: for people "Keep the person's face, identity, hairstyle and body exactly the same." together with the other unchanged parts named in the rule, and end with "Keep everything else unchanged."
    - A common instruction for the whole series may be given. Apply only what it adds or changes compared with Picture 1 and never let it override the variable; parts that already match Picture 1 are ignored.
    - The other states of the series are listed only so that this picture stays clearly distinct from them – never use them.
    - Positive phrasing only, except "Remove the …" when something has to disappear.
    - 25 to 90 words, one paragraph, English, no markdown, no lists.

    Output: only the final edit instruction – no introduction, no explanation, no quotation marks around it.
    """

    static func seriesRequest(variable: SeriesVariable, name: String, value: String, common: String, others: [String]) -> String {
        var parts = [
            variable == .custom ? "Variable: \(name)" : "Variable: \(variable.englishName)",
            "Rule for this variable: \(variable.rule)",
            "New state for this picture: \"\(value)\"",
        ]
        if let block = variable.catalogText(for: value) {
            parts.append("Building block text for this state (use it): \(block)")
        }
        if !others.isEmpty {
            parts.append("Other states in the same series (do not use): " + others.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        if !common.isEmpty {
            parts.append("Common instruction for the whole series:\n\"\"\"\n\(common)\n\"\"\"")
        }
        return parts.joined(separator: "\n")
    }

    /// Ohne Gemma: einfacher Prompt nach der Regel der Variable.
    static func seriesFallback(variable: SeriesVariable, name: String, value: String) -> String {
        let v = variable.catalogText(for: value) ?? value
        return switch variable {
        case .outfit: "Change the clothing of the person to \(v). Keep the person's face, identity, hairstyle, pose, background and lighting exactly the same."
        case .pose: "Change the pose of the person: \(v). Keep the person's face, identity, clothing, background and lighting exactly the same."
        case .background: "Replace the background with \(v) and match the light on the person to it. Keep the person's face, identity, clothing and pose exactly the same."
        case .colors: "Change the colors: \(v). Keep the shapes, materials, the person's identity, pose and the composition the same."
        case .lighting: "Relight the scene: \(v). Keep the person's face, identity, clothing, pose and background the same."
        case .expression: "Change the facial expression of the person: \(v). Keep the identity, hairstyle, clothing, pose, background and lighting exactly the same."
        case .hair: "Change the hairstyle of the person to \(v). Keep the face, identity, clothing, pose, background and lighting exactly the same."
        case .camera: "Rotate the camera: \(v). Keep the person, clothing, setting, lighting and style the same."
        case .style: "Restyle Picture 1 as \(v). Keep the composition, the people, their poses and the content the same."
        case .custom: "Change the \(name) to \(v). Keep everything else in Picture 1 unchanged, especially the person's face and identity."
        }
    }

    // MARK: Labs

    /// Qwen-Image-Edit-2511 in Draw Things: Canvas = Picture 1, Moodboards = Picture 2 … 4.
    /// Nach Alibabas eigener Anleitung zum Umschreiben von Edit-Prompts („Edit Prompt Enhancer“ in
    /// QwenLM/Qwen-Image, `prompt_utils.py`): direkt und knapp, „Replace Y with X“ plus Merkmale von X,
    /// bei mehreren Bildern genau sagen, aus welchem Bild was kommt, Personen in ihren Kernmerkmalen festhalten.
    /// „Picture N“ ist die Beschriftung, mit der das Modell die Eingabebilder bekommt („Picture 1: <Bild>“).
    static let labsCompose = """
    You are the prompt engineer of "DrawThings Studio Labs". The user edits one picture in Draw Things with Qwen-Image-Edit-2511 using several input pictures. The model receives them labelled "Picture 1", "Picture 2" … in input order. Picture 1 is the canvas – the base picture that gets edited; its background, composition and framing stay unless the user asks otherwise. The moodboard pictures follow as Picture 2, Picture 3 and Picture 4, in the order of the list in the request. You see every picture yourself, attached in the same order.

    For each picture the user writes in German what should happen. The user may call the pictures "Image N", "Bild N" or "Picture N" – the numbers are the same. A wish written at a moodboard picture usually says what to take from that picture and where it goes in Picture 1.

    Write ONE direct and specific edit instruction in English, following Alibaba's rules for Qwen-Image-Edit:
    - Name the pictures only as "Picture 1", "Picture 2" … from the list. Say clearly which element of Picture 1 changes and which picture the new element comes from.
    - Anchor every element with a few features you actually see: "the woman in the red dress on the left of Picture 1", "the man in the grey hoodie from Picture 2".
    - Replacements: "Replace <element of Picture 1> with <element from Picture N>", then the key visual features of the new element. Additions: what, where, how big. Removals: "Remove the …".
    - Do only what the user asks. Never add changes, effects, color grading, blur, relighting or restyling the user did not ask for.
    - If a wish is unclear or has a typo, take the reading that changes the least – for example "belieben" is a typo of "bleiben" (= stays) – and report it in "assumptions".
    - End with one "Keep … unchanged" sentence that names what the user wants to stay and the main parts of Picture 1 that are not edited (background, other people, text).
    - Text in the picture is quoted exactly in double quotes, e.g. keep the text "OPEN" unchanged. A style change goes last.
    - Usually 25 to 80 words, longer only for several changes. One paragraph, no markdown, no lists.

    People and identity – the most important part:
    - Replacing a person with a person from another picture: "Replace the <anchor> in Picture 1 with the <anchor> from Picture N." Keep the new person's core look exactly as in Picture N: face, facial features, ethnicity, gender, age, hairstyle, skin tone, body shape and outfit (unless the user changes the outfit). Place them at the position and scale of the replaced person. Take the pose from Picture N only if the user asks for it, otherwise the pose of the replaced person. Light and shadows on them match Picture 1.
    - Every person who stays keeps face, identity, expression, pose and clothing unchanged.
    - Changes to a person (clothes, hair, expression, make-up) stay natural and subtle and keep the identity, e.g. "Replace the man's hat with a dark brown beret; keep his face, smile, short hair and gray jacket unchanged."

    Example
    Wishes – Picture 1 (canvas): "Hintergrund bleibt, die Frau links wird ersetzt". Picture 2 (moodboard 1): "Diese Frau soll dort stehen, mit ihrer Pose".
    Prompt: Replace the woman in the beige coat on the left of Picture 1 with the young woman in the green leather jacket from Picture 2, in the same pose as in Picture 2, at the same position and scale. Keep her face, facial features, long dark hair, skin tone and green leather jacket exactly as in Picture 2, with lighting that matches Picture 1. Keep the street background, the other people and the shop sign of Picture 1 unchanged.

    In "check" explain in German, in 2 to 3 short sentences, what the prompt asks Draw Things to do and which picture provides what.
    In "assumptions" write in German what was unclear and how you read it – an empty string if everything was clear.
    In "has_person" say whether a person is visible in any of the pictures.

    Answer with JSON only.
    """

    struct LabPicture {
        let number: Int
        let place: String
        let wish: String
    }

    static func labsComposeRequest(pictures: [LabPicture], general: String, previous: String?, correction: String?) -> String {
        var parts = ["Pictures (attached in this order):"]
        for picture in pictures {
            let wish = picture.wish.isEmpty
                ? (picture.number == 1 ? "(none – it is the base, keep it)" : "(none – use it only if another wish refers to it)")
                : "\"\(picture.wish)\""
            parts.append("- Picture \(picture.number) = \(picture.place). Wish: \(wish)")
        }
        if !general.isEmpty { parts.append("Wish for the whole picture: \"\(general)\"") }
        if let previous, let correction {
            parts.append("Your previous prompt:\n\"\"\"\n\(previous)\n\"\"\"")
            parts.append("Correction from the user (German) – rewrite the prompt with it applied and keep everything else: \"\(correction)\"")
        }
        return parts.joined(separator: "\n")
    }

    static let labsComposeSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "prompt": ["type": "string"],
            "check": ["type": "string"],
            "assumptions": ["type": "string"],
            "has_person": ["type": "boolean"],
        ],
        "required": ["prompt", "check", "assumptions", "has_person"],
        "additionalProperties": false,
    ]

    /// Fehlt im Prompt jede Angabe zur Identität, obwohl Personen zu sehen sind, hängt die App diesen Satz an.
    static let labsIdentityFallback = "Keep the face, facial features, hairstyle, skin tone and identity of every person exactly as in their source picture."

    // MARK: Analyse

    static let reversePrompt = """
    You are the vision analyst of "DrawThings Studio". Write a text-to-image prompt for Qwen-Image 1.0 that would recreate this image as closely as possible.
    One fluent English paragraph of 80 to 170 words in this order: medium and style, main subject (appearance, expression, clothing, pose, action), setting and background, composition and framing, camera viewpoint, lens and depth of field, lighting, color palette, mood. Quote visible text exactly in double quotes and say where it is. Positive phrasing only, no negations. No introduction such as "The image shows", no markdown.
    Output only the prompt.
    """

    static let subject = """
    You are the vision analyst of "DrawThings Studio". Identify the main subject (or subjects) of the image and describe it so the description can be pasted directly into an image prompt.
    Always write in English. Describe only the subject: what or who it is, apparent age and gender for people, build, skin tone, hair (color, length, style), eyes, distinctive facial features, facial hair, expression, visible clothing and accessories, and pose. Leave out background, lighting, camera and image quality.
    One fluent paragraph of 2 to 4 sentences. No markdown, no lists, no introduction such as "The image shows".
    """

    static let style = """
    You are the vision analyst of "DrawThings Studio". Analyze the visual style of this image: medium, camera viewpoint and framing, lens and depth of field, lighting (direction, softness, color temperature), color grading, film look, texture and mood.
    Write it as one English prompt paragraph of 40 to 90 words that can be appended to another image prompt to reproduce this style on a different subject. Do not describe the subject or the content.
    Output only the paragraph.
    """

    static let question = """
    You are the vision analyst of "DrawThings Studio". Answer the user's question about the image precisely and briefly in German. If the user asks for a prompt, write the prompt in English.
    """

    static func reference(_ role: ReferenceRole) -> String {
        let task: String
        switch role {
        case .identity:
            task = "Describe the person: apparent age, gender, skin tone, face shape, eyes, eyebrows, nose, lips, hair (color, length, style), facial hair and distinctive marks. Leave out clothing, pose and background. 2 to 3 sentences."
        case .outfit:
            task = "Describe only the clothing and accessories in detail: garment types, colors, materials, patterns, fit, layering, shoes and jewelry. Start with \"wearing\". 1 to 3 sentences."
        case .footwear:
            task = "Describe only the shoes in detail: type, colors, materials, sole, heel, laces, logos and details. Start with \"wearing\". 1 to 2 sentences."
        case .accessory:
            task = "Describe only the main accessory (bag, jewelry, glasses, hat, watch …) in detail: type, shape, colors, materials, hardware and details. 1 to 2 sentences."
        case .location:
            task = "Describe only the location: type of place, architecture or landscape, important objects, materials, time of day, weather and light. Leave out people. 2 to 3 sentences."
        case .style:
            task = "Describe only the visual style: medium, color grading, lighting, contrast, texture, film look and mood. Leave out the content. 2 to 3 sentences."
        case .pose:
            task = "Describe only the body pose and gesture of the main person: stance, weight distribution, arm and hand positions, head tilt, gaze direction and orientation to the camera. 1 to 2 sentences."
        case .object:
            task = "Describe the main object or product precisely: type, shape, colors, materials, surface finish, logos or printed text (quoted exactly) and proportions. 2 to 3 sentences."
        case .general:
            task = "Describe the main content of the image. 2 to 3 sentences."
        }
        return """
        You are the vision analyst of "DrawThings Studio". \(task)
        Write in English as a prompt fragment that can be pasted into an image prompt. No markdown, no introduction such as "The image shows".
        """
    }

    /// Beschreibung für eine eigene Asset-Kategorie („hairstyle“, „tattoo“, „car“ …).
    static func reference(subject: String) -> String {
        """
        You are the vision analyst of "DrawThings Studio". Describe only the \(subject) in this image in detail: type, shape, colors, materials, patterns, proportions and distinctive details. Leave out everything else. 1 to 3 sentences.
        Write in English as a prompt fragment that can be pasted into an image prompt. No markdown, no introduction such as "The image shows".
        """
    }

    /// Name einer eigenen Asset-Kategorie (oft Deutsch) → kurzes englisches Thema für Prompts.
    static let assetSubject = """
    You name the topic of a category of reference images for image prompts. Translate the category name into a short English noun phrase in singular, lowercase, as it would appear in an image prompt – for example "Frisuren" → "hairstyle", "Tattoos" → "tattoo", "Autos" → "car", "Brillen" → "pair of glasses". Output only the phrase.
    """

    // MARK: Charaktere

    /// Beschreibung eines Charakters aus seinem Raster – Text-Anker für den Prompt.
    static let personaDescription = """
    You are the vision analyst of "DrawThings Studio". The image is a reference sheet that shows one and the same person from several angles.
    Describe this person so the description can anchor their identity in an image prompt: apparent age, gender, skin tone, face shape, eyes, eyebrows, nose, lips, hair (color, length, style, parting), facial hair, glasses and distinctive marks.
    Leave out clothing, pose, background and the sheet layout. 2 to 3 sentences in English, no markdown, no introduction such as "The image shows".
    """

    /// Szene für den Charaktertest: kurze Idee (oft Deutsch) → englischer Prompt-Baustein.
    static let personaScene = """
    You are the prompt engineer of "DrawThings Studio". Rewrite the user's scene idea (German or English) as an English prompt fragment for one photograph of a single person: setting, action and pose, framing, camera, lighting and mood – concrete and in positive terms.
    Do not describe the person's face, hair or identity – that comes from a reference image. 30 to 80 words, one paragraph, no markdown.
    Output only the text.
    """

    // MARK: Eigene Bausteine

    static func optionWriter(fragment: Bool) -> String {
        let unit = fragment
            ? "a short English noun phrase that is inserted into a sentence template (it usually starts with \"a\" or \"an\")"
            : "one short English sentence"
        let output = fragment ? "the phrase, without a final period" : "the sentence"
        return """
        You write building blocks for "DrawThings Studio", an app that assembles image prompts for Qwen-Image from building blocks. Each building block contributes \(unit) to the prompt.
        Turn the user's value into exactly one such building block for the given category, in the same style, grammar and length as the examples.
        - The value may be German or another language: write English. Names, brands, trigger words and quoted text stay exactly as written.
        - Describe it concretely and visually, in positive terms.
        - Output only \(output), nothing else.
        """
    }

    static func optionRequest(category: String, examples: [String], value: String) -> String {
        var text = "Category: \(category)\n"
        if !examples.isEmpty {
            text += "Examples:\n" + examples.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return text + "\nValue: \(value)"
    }

    // MARK: Bausteine erkennen

    /// Diese Gruppen versucht Gemma in einem Bild wiederzuerkennen.
    static var recognizableGroups: [String] {
        [
            "motiv/subjekt", "motiv/mimik", "motiv/blick", "motiv/gesicht", "motiv/koerper",
            "pose/ganzkoerper", "kleidung/outfit", "kleidung/oberteil", "kleidung/hose", "kleidung/schuhe",
            "ort/innen", "ort/stadt", "ort/natur",
            "kamera/ausschnitt", "kamera/winkel", "kamera/licht",
            "bildkomposition/farbe-look", "bildkomposition/stimmung",
        ].filter { Catalog.shared.group($0) != nil }
    }

    static let recognize = """
    You are the vision analyst of "DrawThings Studio", an app with building blocks for image prompts. Look at the image and pick, for every category, the option that matches the image best.
    Use "none" when the category does not apply or nothing fits clearly (for example a facial expression when no face is visible). For list categories pick at most 3 options, or an empty list.
    Only use option ids from the catalog. Answer with JSON only.
    """

    static func recognizeCatalog() -> String {
        recognizableGroups.compactMap { key -> String? in
            guard let group = Catalog.shared.group(key) else { return nil }
            let options = group.options.map { "\($0.id)=\($0.name)" }.joined(separator: ", ")
            return "\(key) (\(group.multi ? "list" : "single")): \(options)"
        }.joined(separator: "\n")
    }

    static func recognizeSchema() -> [String: Any] {
        var properties: [String: Any] = [:]
        for key in recognizableGroups {
            guard let group = Catalog.shared.group(key) else { continue }
            let ids = group.options.map(\.id)
            if group.multi {
                properties[key] = ["type": "array", "items": ["type": "string", "enum": ids], "maxItems": 3]
            } else {
                properties[key] = ["type": "string", "enum": ids + ["none"]]
            }
        }
        return [
            "type": "object",
            "properties": properties,
            "required": Array(properties.keys),
            "additionalProperties": false,
        ]
    }
}

extension SeriesVariable {
    var englishName: String {
        switch self {
        case .outfit: "clothing and accessories"
        case .pose: "body pose and gesture"
        case .background: "setting and background"
        case .colors: "colors"
        case .lighting: "lighting"
        case .expression: "facial expression"
        case .hair: "hairstyle"
        case .camera: "camera viewpoint and framing"
        case .style: "visual style"
        case .custom: "custom"
        }
    }

    /// Was sich ändern darf und was gleich bleiben muss.
    var rule: String {
        switch self {
        case .outfit:
            "Change only the clothing and accessories. Describe the new garments concretely: type, color, material, fit and how they are worn. Keep the face, identity, hairstyle, body shape, pose, background, lighting and framing exactly the same."
        case .pose:
            "Change only the body pose and gesture: stance, weight, arm and hand positions, head tilt and gaze. Keep the face, identity, clothing, background, lighting and framing the same; extend the framing naturally only if the new pose needs it."
        case .background:
            "Change only the setting and background. Describe the new place concretely and adapt the light on the person so it matches the new environment. Keep the person's face, identity, hairstyle, clothing, pose and the framing exactly the same."
        case .colors:
            "Change only the colors the value describes – of the clothing, of objects or the whole color palette. Keep shapes, materials, the person's identity and natural skin tone, the pose, the composition and the light direction the same."
        case .lighting:
            "Relight the scene only: describe the new light concretely – direction, softness, color temperature, time of day, shadows and highlights. Keep the person's face, identity, clothing, pose, background content and framing the same."
        case .expression:
            "Change only the facial expression: mouth, eyes, eyebrows and gaze. Keep the identity, facial features, hairstyle, clothing, pose, background and lighting exactly the same."
        case .hair:
            "Change only the hairstyle: cut, length, styling (and hair color only if the value asks for it). Keep the face, identity, clothing, pose, background and lighting exactly the same."
        case .camera:
            "Change only the camera viewpoint or framing with camera vocabulary (front view, left side view, back view, front-left quarter view, low-angle shot, high-angle shot, close-up, medium shot, wide shot), e.g. \"Rotate the camera to a left side view of the woman.\" Keep the person, clothing, setting, lighting and style the same."
        case .style:
            "Restyle Picture 1 in the new visual style and describe it concretely: medium, technique, color treatment and texture. Keep the composition, the people, their poses and the content the same."
        case .custom:
            "Change only the aspect named by the variable, to the new state. Keep everything else in Picture 1 the same – especially a person's face and identity."
        }
    }

    /// Englischer Bausteintext, wenn der Wert genau einem Baustein der passenden Kategorien entspricht.
    @MainActor
    func catalogText(for value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for key in catalogKeys {
            guard let group = Catalog.shared.group(key),
                  let option = group.options.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }),
                  option.text != option.name else { continue }
            return option.text
        }
        return nil
    }
}
