import Foundation

/// A dish estimated by the model from a description or a photo.
struct AIDishEstimate: Codable, Equatable {
    struct Ingredient: Codable, Equatable {
        var name: String
        var grams: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
        var sugar: Double
        var saturatedFat: Double
        var sodiumMg: Double
        var potassiumMg: Double
        var calciumMg: Double
        var ironMg: Double

        enum CodingKeys: String, CodingKey {
            case name, grams, calories, protein, carbs, fat, fiber, sugar
            case saturatedFat = "saturated_fat"
            case sodiumMg = "sodium_mg"
            case potassiumMg = "potassium_mg"
            case calciumMg = "calcium_mg"
            case ironMg = "iron_mg"
        }

        /// Nutrients of the whole ingredient portion.
        var nutrients: NutrientProfile {
            NutrientProfile([
                .calories: calories, .protein: protein, .carbs: carbs, .fat: fat,
                .fiber: fiber, .sugar: sugar, .saturatedFat: saturatedFat,
                .sodium: sodiumMg, .potassium: potassiumMg, .calcium: calciumMg, .iron: ironMg,
            ])
        }

        var dishIngredient: DishIngredient {
            let safeGrams = max(grams, 1)
            return DishIngredient(name: name, grams: safeGrams, nutrientsPer100g: nutrients.scaled(by: 100 / safeGrams))
        }
    }

    var name: String
    var ingredients: [Ingredient]
    /// 0...1, how sure the model is about the portion sizes.
    var confidence: Double
    var notes: String

    var totalGrams: Double { ingredients.map(\.grams).reduce(0, +) }

    var totalNutrients: NutrientProfile {
        NutrientProfile.sum(ingredients.map(\.nutrients))
    }

    /// Builds a food item (per 100 g) from this estimate so it can be logged
    /// and reused like any other dish.
    func makeFoodItem() -> FoodItem {
        let grams = max(totalGrams, 1)
        return FoodItem(
            name: name,
            servingGrams: grams,
            servingLabel: String(localized: "1 dish"),
            nutrientsPer100g: totalNutrients.scaled(by: 100 / grams),
            ingredients: ingredients.map(\.dishIngredient),
            source: .ai
        )
    }
}

enum AIFoodError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case refused(String?)
    case http(Int, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return String(localized: "ai.error.missingKey")
        case .invalidResponse:
            return String(localized: "ai.error.invalidResponse")
        case .refused(let reason):
            return reason ?? String(localized: "ai.error.refused")
        case .http(let code, let message):
            return String(localized: "ai.error.http \(code) \(message)")
        case .emptyOutput:
            return String(localized: "ai.error.empty")
        }
    }
}

/// Calls the Claude Messages API directly over HTTPS (there is no official
/// Swift SDK) to estimate the nutrition of a dish.
final class AIFoodService {
    static let shared = AIFoodService()

    /// Model used for estimates. Opus 5.5 is the default; it can be changed
    /// from settings.
    static let defaultModel = "claude-opus-5-5"
    static let modelDefaultsKey = "ai.model"

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var model: String {
        UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? Self.defaultModel
    }

    func estimate(description: String, language: String) async throws -> AIDishEstimate {
        let prompt = String(
            localized: "ai.prompt.description \(description)",
            comment: "Instruction sent to the model together with the user's dish description"
        )
        return try await request(content: [["type": "text", "text": prompt]], language: language)
    }

    func estimate(imageJPEG: Data, hint: String, language: String) async throws -> AIDishEstimate {
        let prompt = hint.isEmpty
            ? String(localized: "ai.prompt.photo")
            : String(localized: "ai.prompt.photoWithHint \(hint)")
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageJPEG.base64EncodedString(),
                ],
            ],
            ["type": "text", "text": prompt],
        ]
        return try await request(content: content, language: language)
    }

    // MARK: - Request

    private func request(content: [[String: Any]], language: String) async throws -> AIDishEstimate {
        guard let apiKey = AppSecrets.claudeAPIKey, !apiKey.isEmpty else {
            throw AIFoodError.missingAPIKey
        }

        let system = """
        You are a registered dietitian estimating the nutrition of meals for a food diary. \
        Break the dish into its visible or stated ingredients with realistic portion sizes in grams, \
        and give nutrition values for each ingredient portion using standard food composition tables. \
        Write ingredient and dish names in the language with code "\(language)". \
        Use 0 for any micronutrient you cannot estimate. Be concise in notes (one sentence).
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": [
                "effort": "medium",
                "format": [
                    "type": "json_schema",
                    "schema": Self.outputSchema,
                ],
            ],
            "fallbacks": "default",
        ]

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AIFoodError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw AIFoodError.http(http.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIFoodError.invalidResponse
        }
        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw AIFoodError.refused(details?["explanation"] as? String)
        }
        guard let blocks = json["content"] as? [[String: Any]] else { throw AIFoodError.invalidResponse }
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty, let textData = text.data(using: .utf8) else { throw AIFoodError.emptyOutput }
        return try JSONDecoder().decode(AIDishEstimate.self, from: textData)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    /// JSON schema for structured output; every property is required and
    /// objects forbid extra keys, as the API demands.
    static let outputSchema: [String: Any] = {
        let number: [String: Any] = ["type": "number"]
        let ingredient: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "grams": number,
                "calories": number,
                "protein": number,
                "carbs": number,
                "fat": number,
                "fiber": number,
                "sugar": number,
                "saturated_fat": number,
                "sodium_mg": number,
                "potassium_mg": number,
                "calcium_mg": number,
                "iron_mg": number,
            ],
            "required": [
                "name", "grams", "calories", "protein", "carbs", "fat", "fiber", "sugar",
                "saturated_fat", "sodium_mg", "potassium_mg", "calcium_mg", "iron_mg",
            ],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "ingredients": ["type": "array", "items": ingredient],
                "confidence": number,
                "notes": ["type": "string"],
            ],
            "required": ["name", "ingredients", "confidence", "notes"],
            "additionalProperties": false,
        ]
    }()
}
