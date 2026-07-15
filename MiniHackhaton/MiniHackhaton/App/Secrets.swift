import Foundation

/// Local-only secrets, kept out of source control by convention: the committed value must
/// always stay empty. Paste your real OpenAI API key here while developing, and revert
/// before committing (`git checkout -- MiniHackhaton/MiniHackhaton/App/Secrets.swift`).
enum Secrets {
    static let openAIAPIKey = ""
}
