import Foundation

// MARK: - Request

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

// MARK: - Response

struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message

        struct Message: Decodable {
            let content: String
        }
    }

    var firstContent: String? { choices.first?.message.content }
}
