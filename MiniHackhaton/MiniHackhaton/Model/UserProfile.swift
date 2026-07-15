import Foundation
import Observation

struct UserProfile: Codable, Equatable {
    enum Gender: String, Codable, CaseIterable, Identifiable {
        case male
        case female

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .male: return "Male"
            case .female: return "Female"
            }
        }
    }

    var name: String
    var age: Int
    var gender: Gender
    var weightKg: Double
    var heightCm: Double

    /// One-line summary of the user, used to personalize LLM prompts.
    var promptDescription: String {
        "\(gender.displayName), \(age) years old, weight \(Int(weightKg)) kg, height \(Int(heightCm)) cm"
    }
}

/// Owns the persisted profile. `profile` is nil until onboarding completes, which is
/// what `RootView` uses to decide between the onboarding flow and the scan home.
@Observable
final class UserProfileStore {
    private static let defaultsKey = "userProfile"

    var profile: UserProfile? {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey) {
            profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        }
    }

    private func persist() {
        guard let profile, let data = try? JSONEncoder().encode(profile) else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
