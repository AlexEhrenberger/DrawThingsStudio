import CoreGraphics
import Foundation

/// Was Draw Things gerade eingestellt hat (GET /). LoRAs werden bewusst ignoriert.
struct DrawThingsConfig: Equatable {
    var model: String
    var width: Int
    var height: Int
    var steps: Int?

    var size: CGSize { CGSize(width: width, height: height) }

    var modelDisplayName: String {
        let name = model.replacingOccurrences(of: ".ckpt", with: "")
        let known: [(String, String)] = [
            ("qwen_image_edit_2511", "Qwen Image Edit 2511"),
            ("qwen_image_edit_2509", "Qwen Image Edit 2509"),
            ("qwen_image_edit", "Qwen Image Edit"),
            ("qwen_image_2512", "Qwen Image 2512"),
            ("qwen_image_2.1", "Qwen Image 2.1"),
            ("qwen_image_1.0", "Qwen Image 1.0"),
        ]
        return known.first { name.hasPrefix($0.0) }?.1 ?? name
    }
}

extension DrawThingsConfig {
    /// Lesbarer Name für eine Modelldatei.
    static func displayName(for file: String) -> String {
        DrawThingsConfig(model: file, width: 0, height: 0).modelDisplayName
    }
}

/// Modelle, die in Draw Things installiert sind (nur Bildmodelle, keine LoRAs, Encoder oder Upscaler).
enum DrawThingsModels {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Containers/com.liuliu.draw-things/Data/Documents/Models")

    private static let excluded = [
        "lora", "vae", "_vit_", "clip", "t5_", "text_encoder", "qwen_2.5_vl", "qwen_3_vl", "siglip", "moondream",
        "parsenet", "restoreformer", "esrgan", "remacri", "ultrasharp", "4x_", "2x_", "upscale", "controlnet",
        "depth", "canny", "openpose", "scribble", "wan_", "ltx", "hunyuan", "svd_",
    ]

    static func installed() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".ckpt") }
            .filter { file in !excluded.contains { file.lowercased().contains($0) } }
            .sorted { lhs, rhs in
                let lq = lhs.hasPrefix("qwen"), rq = rhs.hasPrefix("qwen")
                return lq != rq ? lq : lhs < rhs
            }
    }
}

struct DrawThingsRequest {
    var prompt: String
    var width: Int
    var height: Int
    /// PNG-Daten. Das erste Bild ist „Picture 1“ für Qwen Image Edit.
    var initImages: [Data] = []
    var model: String?
    var seed: UInt32?

    /// Bewusst ohne `loras`: Draw Things behält dann die LoRAs, die dort eingestellt sind.
    var json: [String: Any] {
        var body: [String: Any] = ["prompt": prompt, "width": width, "height": height]
        if !initImages.isEmpty { body["init_images"] = initImages.map { $0.base64EncodedString() } }
        if let model { body["model"] = model }
        if let seed { body["seed"] = seed }
        return body
    }
}

/// HTTP-API von Draw Things (Einstellungen › API-Server › HTTP, Port 7860).
/// Gesendet werden nur Prompt und Bildgröße (= Seitenverhältnis); alles andere –
/// Sampler, Schritte, LoRAs – bleibt so, wie es in Draw Things eingestellt ist.
struct DrawThingsClient {
    var baseURL: URL

    init(baseURL: String) {
        self.baseURL = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) ?? URL(string: "http://127.0.0.1:7860")!
    }

    func config() async throws -> DrawThingsConfig {
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.local.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError("Draw Things hat keine Einstellungen geliefert.")
        }
        return DrawThingsConfig(
            model: object["model"] as? String ?? "",
            width: object["width"] as? Int ?? 1024,
            height: object["height"] as? Int ?? 1024,
            steps: object["steps"] as? Int
        )
    }

    func generate(_ job: DrawThingsRequest) async throws -> [Data] {
        let path = job.initImages.isEmpty ? "sdapi/v1/txt2img" : "sdapi/v1/img2img"
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: job.json)
        request.timeoutInterval = 60 * 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.local.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .cannotFindHost {
            throw ServiceError("Draw Things ist nicht erreichbar. Ist der API-Server (HTTP, Port 7860) eingeschaltet?")
        }

        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) || object?["images"] == nil {
            let detail = object?["detail"] as? String ?? object?["error"] as? String
                ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ServiceError("Draw Things: \(detail)")
        }
        let images = (object?["images"] as? [String] ?? []).compactMap { Data(base64Encoded: $0) }
        guard !images.isEmpty else {
            throw ServiceError("Draw Things hat kein Bild zurückgegeben. Ist in Draw Things ein Projekt geöffnet?")
        }
        return images
    }
}
