import Foundation

enum OpenAIError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an unexpected response from the AI endpoint."
        case .apiError(let statusCode):
            return "AI request failed with status \(statusCode)."
        case .emptyReply:
            return "The AI returned an empty reply."
        }
    }
}

/// Thin client for the chat-completions LLM endpoint configured in `Constants`.
///
/// `complete(system:user:)` is the generic entry point; `nutritionAdvice(for:)` wraps it
/// with a prompt tuned for this app: a short, plain-text explanation of a scan result,
/// phrased to be read aloud by VoiceOver.
final class OpenAIService {
    nonisolated(unsafe) static let shared = OpenAIService()

    /// Shared persona for every nutrition prompt: short plain-text English replies,
    /// safe to read aloud via VoiceOver, no medical diagnosis.
    private static let nutritionSystemPrompt = """
    You are a nutrition assistant inside a nutrition-label scanning app for blind users. \
    Reply in English, at most 3 sentences, in plain text without markdown or emoji \
    because replies are read aloud by VoiceOver. Do not give medical diagnoses.
    """

    /// Bearer token sent with each request. Leave empty if the endpoint doesn't require one.
    private let apiKey: String

    init(apiKey: String = Secrets.openAIAPIKey) {
        self.apiKey = apiKey
    }

    /// Sends one system + user message pair and returns the assistant's reply text.
    nonisolated func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: Constants.aiEndpoint) else { throw OpenAIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(OpenAIRequest(
            model: Constants.aiModel,
            messages: [
                OpenAIRequest.Message(role: "system", content: system),
                OpenAIRequest.Message(role: "user", content: user),
            ]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIError.apiError(statusCode: http.statusCode)
        }

        let reply = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = reply.firstContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw OpenAIError.emptyReply
        }
        return content
    }

    /// Asks for a short spoken-friendly explanation of a scan result: why the product got
    /// its classification and how it fits into a normal diet. Pass `profile` to have the
    /// advice tailored to the user's age, gender, weight, and height.
    nonisolated func nutritionAdvice(for result: HealthScanResult, profile: UserProfile? = nil) async throws -> String {
        let readings = result.items.isEmpty
            ? "none"
            : result.items.map { "\($0.name) \($0.value)" }.joined(separator: ", ")

        var user = """
        A food product was classified as "\(result.classification.displayLabel)" \
        (\(Int(result.classification.confidence * 100))% confidence). \
        Nutrition readings from the label: \(readings).
        """
        if !result.classification.missingFields.isEmpty {
            user += " \(result.classification.missingFields.count) values could not be read and were assumed bad."
        }
        if let profile {
            user += " User profile: \(profile.promptDescription). Tailor the advice to this profile."
        }
        user += " Briefly explain why this product received that classification and give one consumption tip."

        return try await complete(system: Self.nutritionSystemPrompt, user: user)
    }

    /// Asks for a structured recap of everything scanned today: an assessment plus one
    /// food tip and one workout tip. `summary` is the dashboard's pre-built data sentence
    /// (scan counts, calories, top nutrients).
    nonisolated func dailyAdvice(summary: String, profile: UserProfile? = nil) async throws -> DailyAdvice {
        var user = summary
        if let profile {
            user += " User profile: \(profile.promptDescription)."
        }
        user += """
         Based on that data, reply in exactly three lines with this format and nothing else:
        ASSESSMENT: a brief assessment of today's eating pattern in 1 to 2 sentences.
        FOOD: one practical eating tip for the rest of the day.
        WORKOUT: one concrete physical activity suggestion with estimated duration and calories burned.
        """

        let raw = try await complete(system: Self.dailyAdviceSystemPrompt, user: user)
        return DailyAdvice(parsing: raw)
    }

    private static let dailyAdviceSystemPrompt = """
    You are a nutrition assistant inside a nutrition-label scanning app for blind users. \
    Reply in English, in plain text without markdown or emoji because replies are read \
    aloud by VoiceOver. Follow the requested line format exactly. Do not give medical diagnoses.
    """

    /// Asks the model to rate the healthiness of today as a single 0–100 score, weighing
    /// both nutrition intake and physical activity. Powers the home `TodayProgressBar`.
    /// `summary` is the dashboard's pre-built data sentence (scan counts, calories, top
    /// nutrients) with an activity sentence appended by the caller.
    nonisolated func dailyHealthScore(summary: String, profile: UserProfile? = nil) async throws -> DailyHealthScore {
        var user = summary
        if let profile {
            user += " User profile: \(profile.promptDescription)."
        }
        user += """
         Based on that nutrition and activity data, rate how healthy the user's day is as a \
        single integer from 0 to 100, where 0 is very unhealthy and 100 is excellent. Weigh \
        both nutrition quality and physical activity; more activity offsetting the calories \
        eaten should raise the score. Reply in exactly two lines with this format and nothing else:
        SCORE: an integer from 0 to 100.
        REASON: a brief one-sentence justification.
        """

        let raw = try await complete(system: Self.dailyHealthScoreSystemPrompt, user: user)
        guard let parsed = DailyHealthScore(parsing: raw) else {
            throw OpenAIError.emptyReply
        }
        return parsed
    }

    private static let dailyHealthScoreSystemPrompt = """
    You are a nutrition assistant inside a nutrition-label scanning app. Reply in English, in \
    plain text without markdown or emoji. Follow the requested line format exactly and always \
    include a numeric SCORE line. Do not give medical diagnoses.
    """
}

/// A 0–100 daily health score parsed from the LLM's SCORE/REASON reply. Fails to init
/// only when no integer can be found, so callers can fall back to a local calculation.
struct DailyHealthScore: Equatable {
    /// Clamped to 0...100.
    let score: Double
    let reason: String?

    init?(parsing raw: String) {
        let cleaned = raw.replacingOccurrences(of: "**", with: "")
        var foundScore: Double?
        var foundReason: String?

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if foundScore == nil, upper.hasPrefix("SCORE"), let value = Self.firstNumber(in: line) {
                foundScore = min(max(value, 0), 100)
            } else if upper.hasPrefix("REASON") {
                let rest = line.dropFirst("REASON".count)
                    .drop { $0 == ":" || $0 == " " || $0 == "-" }
                foundReason = String(rest)
            }
        }

        // Fallback: no SCORE line, but the reply contains a number somewhere.
        if foundScore == nil, let value = Self.firstNumber(in: cleaned) {
            foundScore = min(max(value, 0), 100)
        }

        guard let score = foundScore else { return nil }
        self.score = score
        self.reason = (foundReason?.isEmpty == false) ? foundReason : nil
    }

    /// First integer/decimal run found in `text`, or nil.
    private static func firstNumber(in text: String) -> Double? {
        var number = ""
        for character in text {
            if character.isNumber || (character == "." && !number.isEmpty) {
                number.append(character)
            } else if !number.isEmpty {
                break
            }
        }
        return Double(number)
    }
}

/// Structured daily advice parsed from the LLM's ASSESSMENT/FOOD/WORKOUT reply.
/// When the reply doesn't follow the format, the whole text lands in `assessment`.
struct DailyAdvice: Equatable {
    let assessment: String?
    let foodTip: String?
    let workoutTip: String?

    init(parsing raw: String) {
        let cleaned = raw.replacingOccurrences(of: "**", with: "")
        var parts: [String: String] = [:]
        var currentKey: String?

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let (key, rest) = Self.keyedLine(line) {
                currentKey = key
                parts[key] = rest
            } else if let currentKey {
                // Continuation of the previous section wrapped onto a new line.
                parts[currentKey, default: ""] += " " + line
            }
        }

        if parts.isEmpty {
            assessment = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            foodTip = nil
            workoutTip = nil
        } else {
            assessment = parts["ASSESSMENT"]
            foodTip = parts["FOOD"]
            workoutTip = parts["WORKOUT"]
        }
    }

    private static func keyedLine(_ line: String) -> (key: String, rest: String)? {
        for key in ["ASSESSMENT", "FOOD", "WORKOUT"] where line.uppercased().hasPrefix(key) {
            let rest = line.dropFirst(key.count)
                .drop { $0 == ":" || $0 == " " || $0 == "-" }
            return (key, String(rest))
        }
        return nil
    }
}
