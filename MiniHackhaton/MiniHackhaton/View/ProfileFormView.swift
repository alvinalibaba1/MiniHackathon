import SwiftUI

/// Collects the rest of the profile (age, gender, weight, height). Used twice:
/// as the second onboarding step (name passed in from `GreetingsView`) and as the
/// profile editor opened from the scan home (existing profile passed in).
struct ProfileFormView: View {
    @State private var name: String
    @State private var ageText: String
    @State private var gender: UserProfile.Gender
    @State private var weightText: String
    @State private var heightText: String
    @State private var appeared = false
    var onSave: (UserProfile) -> Void

    init(name: String = "", existing: UserProfile? = nil, onSave: @escaping (UserProfile) -> Void) {
        _name = State(initialValue: existing?.name ?? name)
        _ageText = State(initialValue: existing.map { String($0.age) } ?? "")
        _gender = State(initialValue: existing?.gender ?? .male)
        _weightText = State(initialValue: existing.map { String(Int($0.weightKg)) } ?? "")
        _heightText = State(initialValue: existing.map { String(Int($0.heightCm)) } ?? "")
        self.onSave = onSave
    }

    /// Valid profile assembled from the current inputs, or nil while any field is invalid.
    private var draft: UserProfile? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let age = Int(ageText), (1...120).contains(age),
              let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")), weight > 0,
              let height = Double(heightText.replacingOccurrences(of: ",", with: ".")), height > 0 else {
            return nil
        }
        return UserProfile(name: trimmedName, age: age, gender: gender, weightKg: weight, heightCm: height)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                avatar
                formCard

                if let bmi {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(bmiCategory.tint)
                            .frame(width: 8, height: 8)
                        Text("BMI \(bmi, specifier: "%.1f") · \(bmiCategory.label)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                }

                saveButton

                Text("This data is used to personalize AI nutrition advice.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .animation(.easeOut(duration: 0.25), value: bmi != nil)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("About You")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
                appeared = true
            }
        }
    }

    // MARK: - Avatar

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 84, height: 84)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(initials)
                    .font(.system(size: 30, design: .rounded).bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldBlock("NAME") {
                TextField("Your name", text: $name)
                    .font(.body)
                    .textContentType(.givenName)
                    .accessibilityLabel("Your name")
            }

            Divider()

            fieldBlock("AGE") {
                HStack(spacing: 6) {
                    TextField("0", text: $ageText)
                        .font(.body)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 64)
                        .accessibilityLabel("Age in years")
                    Text("years")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            Divider()

            fieldBlock("GENDER") {
                HStack {
                    Picker("Gender", selection: $gender) {
                        ForEach(UserProfile.Gender.allCases) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.primary)
                    .padding(.leading, -12)
                    Spacer()
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                fieldBlock("WEIGHT") {
                    HStack(spacing: 6) {
                        TextField("0", text: $weightText)
                            .font(.body)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 56)
                            .accessibilityLabel("Weight in kilograms")
                        Text("kg")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                fieldBlock("HEIGHT") {
                    HStack(spacing: 6) {
                        TextField("0", text: $heightText)
                            .font(.body)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 56)
                            .accessibilityLabel("Height in centimeters")
                        Text("cm")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func fieldBlock(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - BMI

    private var bmi: Double? {
        guard let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")), weight > 0,
              let height = Double(heightText.replacingOccurrences(of: ",", with: ".")), height > 0 else {
            return nil
        }
        let meters = height / 100
        return weight / (meters * meters)
    }

    private var bmiCategory: (label: String, tint: Color) {
        switch bmi ?? 0 {
        case ..<18.5: return ("Underweight", .blue)
        case ..<25: return ("Normal", .green)
        case ..<30: return ("Overweight", .orange)
        default: return ("Obese", .red)
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            if let draft { onSave(draft) }
        } label: {
            Text("Save")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    draft != nil ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.systemGray4)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(draft == nil)
        .animation(.easeOut(duration: 0.2), value: draft == nil)
    }
}

#Preview {
    NavigationStack {
        ProfileFormView(name: "Alvin") { _ in }
    }
}
