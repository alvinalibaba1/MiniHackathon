import SwiftUI
import UIKit

/// Dedicated advice screen, pushed from the home dashboard's "Advice Me" button.
/// Shows today's key numbers up top, an animated "thinking" state while the LLM
/// call runs, then the advice split into assessment / food / workout cards.
struct AdviceView: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    var history: ScanHistoryStore
    let profile: UserProfile?

    private enum Phase: Equatable {
        case loading
        case loaded(DailyAdvice)
        case failed
    }

    @State private var phase: Phase = .loading
    @State private var pulse = false
    @State private var barsAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                healthSummaryCard

                switch phase {
                case .loading:
                    loadingView
                        .transition(.opacity)
                case .loaded(let advice):
                    adviceCards(advice)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .failed:
                    failedView
                        .transition(.opacity)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .animation(.spring(duration: 0.5), value: phase)
        .navigationTitle("Your Advice")
        .navigationBarTitleDisplayMode(.inline)
        .task { await fetchAdvice() }
    }

    // MARK: - Health summary

    /// Which way today leans. Ties resolve toward the worse category, consistent
    /// with the app's "assume the worst until proven otherwise" philosophy.
    private var verdict: (text: String, tint: Color) {
        let counts = history.todayCounts
        if counts.bad >= max(counts.good, counts.healthy) {
            return ("Leaning Unhealthy", .red)
        } else if counts.good >= counts.healthy {
            return ("Leaning Moderate", .orange)
        } else {
            return ("Leaning Healthy", .green)
        }
    }

    /// Only categories that actually occurred today; zero-count rows stay hidden.
    private var presentCategories: [(label: String, icon: String, tint: Color, count: Int)] {
        let counts = history.todayCounts
        return [
            ("Unhealthy", "xmark.octagon.fill", .red, counts.bad),
            ("Moderate", "exclamationmark.circle.fill", .orange, counts.good),
            ("Healthy", "checkmark.seal.fill", .green, counts.healthy),
        ].filter { $0.count > 0 }
    }

    private var healthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Condition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verdict.text)
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(verdict.tint)
            }

            ForEach(Array(presentCategories.enumerated()), id: \.element.label) { index, category in
                categoryRow(
                    label: category.label,
                    icon: category.icon,
                    tint: category.tint,
                    count: category.count,
                    total: history.todayCounts.total,
                    order: index
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { barsAppeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(healthSummarySpoken)
    }

    private func categoryRow(label: String, icon: String, tint: Color, count: Int, total: Int, order: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint.gradient)
                Text(label)
                    .font(.subheadline)
                Spacer()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: barsAppeared && total > 0
                            ? max(geometry.size.width * CGFloat(count) / CGFloat(total), count > 0 ? 10 : 0)
                            : 0)
                }
            }
            .frame(height: 8)
            .animation(.spring(duration: 0.7).delay(Double(order) * 0.15), value: barsAppeared)
        }
    }

    private var healthSummarySpoken: String {
        let details = presentCategories
            .map { "\($0.label.lowercased()) products" }
            .joined(separator: ", ")
        return "Today's condition is \(verdict.text). Today includes \(details)."
    }

    // MARK: - Phases

    private var loadingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor.gradient)
                .symbolEffect(.variableColor.iterative.reversing)
                .scaleEffect(pulse ? 1.1 : 0.92)

            Text("Analyzing your nutrition today…")
                .font(.headline)

            Text("AI is preparing advice based on your scans and profile.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func adviceCards(_ advice: DailyAdvice) -> some View {
        VStack(spacing: 16) {
            if let assessment = advice.assessment, !assessment.isEmpty {
                adviceCard(
                    title: "Today's Assessment",
                    icon: "text.magnifyingglass",
                    tint: .blue,
                    text: assessment
                )
            }
            if let foodTip = advice.foodTip, !foodTip.isEmpty {
                adviceCard(
                    title: "Food Tip",
                    icon: "fork.knife",
                    tint: .orange,
                    text: foodTip
                )
            }
            if let workoutTip = advice.workoutTip, !workoutTip.isEmpty {
                adviceCard(
                    title: "Workout Tip",
                    icon: "figure.run",
                    tint: .accentColor,
                    text: workoutTip
                )
            }
        }
    }

    private func adviceCard(title: String, icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("AI advice is currently unavailable.")
                .font(.headline)
            Button("Try Again") {
                phase = .loading
                pulse = false
                Task { await fetchAdvice() }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func fetchAdvice() async {
        // Keep the thinking animation visible even when the API answers instantly,
        // so the transition doesn't flash.
        async let minimumDelay: Void = { try? await Task.sleep(for: .seconds(1.2)) }()

        do {
            let advice = try await OpenAIService.shared.dailyAdvice(
                summary: history.todaySummaryPrompt,
                profile: profile
            )
            await minimumDelay
            phase = .loaded(advice)
            announceAdvice(advice)
        } catch {
            await minimumDelay
            phase = .failed
        }
    }

    private func announceAdvice(_ advice: DailyAdvice) {
        let spoken = [advice.assessment, advice.foodTip, advice.workoutTip]
            .compactMap { $0 }
            .joined(separator: " ")
        guard !spoken.isEmpty else { return }
        announce("AI advice: \(spoken)")
    }

    /// Speaks the advice when VoiceOver is on. No-op otherwise.
    private func announce(_ message: String) {
        guard voiceOverEnabled else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

#Preview {
    NavigationStack {
        AdviceView(history: ScanHistoryStore(), profile: nil)
    }
}
