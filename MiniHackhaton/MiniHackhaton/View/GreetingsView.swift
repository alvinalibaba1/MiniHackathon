import SwiftUI

/// First onboarding screen: welcomes the user and asks for their name.
struct GreetingsView: View {
    @State private var name = ""
    @State private var appeared = false
    var onContinue: (String) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "leaf.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 8)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            Text("Welcome to NutriDe")
                .font(.system(.largeTitle, design: .rounded).bold())
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text("Scan nutrition labels and learn how healthy your food is. Before we start, what's your name?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .font(.title3)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .textContentType(.givenName)
                .submitLabel(.continue)
                .onSubmit {
                    if !trimmedName.isEmpty { onContinue(trimmedName) }
                }
                .accessibilityLabel("Your name")
                .padding(.top, 8)

            Spacer()

            Button {
                onContinue(trimmedName)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(trimmedName.isEmpty)
        }
        .padding(24)
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) {
                appeared = true
            }
        }
    }
}

#Preview {
    GreetingsView { _ in }
}
