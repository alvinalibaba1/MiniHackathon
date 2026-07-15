import AVFoundation
import SwiftUI

/// App entry flow: onboarding (greetings → profile form) on first launch,
/// straight to the camera scan home once a profile is saved.
struct RootView: View {
    @State private var store = UserProfileStore()
    @State private var onboardingPath: [String] = []

    var body: some View {
        if store.profile != nil {
            HomeView(profileStore: store)
        } else {
            NavigationStack(path: $onboardingPath) {
                GreetingsView { name in
                    onboardingPath.append(name)
                }
                .navigationDestination(for: String.self) { name in
                    ProfileFormView(name: name) { profile in
                        // Ask for camera access up front, while still in onboarding,
                        // so the scan button works immediately later. Home shows up
                        // once the user answers the dialog, whatever the answer.
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            DispatchQueue.main.async {
                                store.profile = profile
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
}
