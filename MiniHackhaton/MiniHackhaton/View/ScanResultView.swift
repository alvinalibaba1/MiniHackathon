import SwiftUI
import UIKit

/// Result sheet shown after a successful scan: the captured photo, the health
/// classification banner, and the readings parsed off the label. The banner pops
/// in with a spring and the rows fade in staggered.
struct ScanResultView: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let result: ScanDisplayResult
    /// Called by the "Done" button; the presenter closes both this sheet and the camera.
    var onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: result.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: appeared)
                        .accessibilityHidden(true)

                    ClassificationBanner(classification: result.scan.classification)
                        .scaleEffect(appeared ? 1 : 0.85)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(duration: 0.5, bounce: 0.4).delay(0.1), value: appeared)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nutrition Facts")
                            .font(.headline)
                            .padding(.bottom, 4)
                        ForEach(Array(result.scan.items.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.value)
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.spring(duration: 0.4).delay(0.2 + Double(index) * 0.05), value: appeared)
                            .accessibilityElement(children: .combine)
                            if index < result.scan.items.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    if !topNutrients.isEmpty {
                        topNutrientsCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.spring(duration: 0.4).delay(0.35), value: appeared)
                    }

                    activitiesCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.spring(duration: 0.4).delay(0.45), value: appeared)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
        .onAppear {
            appeared = true
            announce(spokenSummary)
        }
    }

    // MARK: - Top nutrients

    /// This product's three highest %DV readings. Only %DV fields are ranked —
    /// they share a comparable scale, unlike raw kcal/gram readings.
    private var topNutrients: [(field: NutrientField, dv: Double)] {
        NutrientField.integerFields
            .compactMap { field in
                result.scan.facts[field.rawValue].map { (field, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0 }
    }

    private var topNutrientsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top Nutrients in This Product")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(Array(topNutrients.enumerated()), id: \.element.field) { index, entry in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.gradient, in: Circle())
                    Text(entry.field.displayName)
                    Spacer()
                    Text(FDAReference.massText(fromDV: entry.dv, field: entry.field) ?? "-")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if index < topNutrients.count - 1 {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Activities

    private var productCalories: Double? {
        result.scan.facts[NutrientField.calories.rawValue]
    }

    private var activitiesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Balancing Activities")
                .font(.headline)
            if let productCalories, productCalories > 0 {
                Text("This product is about \(Int(productCalories)) kcal per serving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(SuggestedActivity.daily.enumerated()), id: \.element.id) { index, activity in
                HStack(spacing: 12) {
                    Image(systemName: activity.icon)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.name)
                        Text(activity.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("−\(Int(activity.kcalBurned)) kcal")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if index < SuggestedActivity.daily.count - 1 {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var spokenSummary: String {
        let classification = result.scan.classification
        var summary = "Scan result: \(classification.displayLabel), \(Int(classification.confidence * 100)) percent confidence."
        if !classification.missingFields.isEmpty {
            summary += " \(classification.missingFields.count) nutrition values could not be read and were assumed bad."
        }
        return summary
    }

    /// Speaks the scan verdict aloud so a VoiceOver user hears it without having
    /// to locate the banner by touch. No-op when VoiceOver is off.
    private func announce(_ message: String) {
        guard voiceOverEnabled else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

private struct ClassificationBanner: View {
    let classification: HealthClassification

    private var tint: Color {
        switch classification.label {
        case "sehat": return .green
        case "cukup sehat": return .orange
        case "kurang sehat": return .red
        default: return .gray
        }
    }

    private var icon: String {
        switch classification.label {
        case "sehat": return "checkmark.seal.fill"
        case "cukup sehat": return "exclamationmark.circle.fill"
        case "kurang sehat": return "xmark.octagon.fill"
        default: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(tint.gradient)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(classification.displayLabel)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(Int(classification.confidence * 100))% confident")
                        .font(.system(.subheadline, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if !classification.missingFields.isEmpty {
                    Text("\(classification.missingFields.count) values could not be read and were assumed pessimistically (close to an unhealthy profile).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
