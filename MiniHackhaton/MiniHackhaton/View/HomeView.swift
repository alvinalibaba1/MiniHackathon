import SwiftUI

/// Home dashboard: today's bad/good/healthy progress bar on top, an "Advice Me"
/// button that pushes the AI advice screen, and a tabbed "Today" list
/// (top 3 nutrients / suggested activities). The camera opens from the scan button.
struct HomeView: View {
    var profileStore: UserProfileStore

    @State private var history = ScanHistoryStore()
    @State private var isShowingCamera = false
    @State private var isEditingProfile = false
    @State private var isShowingAdvice = false
    @State private var selectedTodayTab: TodayTab = .nutrition

    /// Activities shown in the "Today" Activity tab. Starts empty; populated with
    /// dummy data when the user taps Sync (placeholder for real HealthKit sync).
    @State private var syncedActivities: [SuggestedActivity] = []
    @State private var isSyncingActivities = false

    /// Total kcal burned by the synced activities. Zero until the user syncs, so the
    /// progress bar's activity coverage only counts once activities are pulled in.
    private var syncedActivityBurn: Double {
        syncedActivities.reduce(0) { $0 + $1.kcalBurned }
    }

    /// AI-computed 0–100 daily score from OpenAIService, nil until it returns (or on
    /// failure). Falls back to the local heuristic so the bar always has a value.
    @State private var aiScore: Double?
    @State private var isScoringToday = false
    /// `scoreInputsKey` the cached `aiScore` was computed for. Prevents re-calling the
    /// API on view reappearance when nutrition and activity are unchanged.
    @State private var scoredInputsKey: String?

    /// Score shown by the progress bar: prefer the AI value, fall back to the local
    /// calculation. Nil (empty state) only when there are no scans today.
    private var displayedScore: Double? {
        guard !history.todayRecords.isEmpty else { return nil }
        return aiScore ?? history.todayScore(activityBurn: syncedActivityBurn)
    }

    /// Changes whenever an input to the score changes, so `.task(id:)` re-asks the model.
    private var scoreInputsKey: String {
        "\(history.todayRecords.count)|\(Int(history.todayCalories))|\(Int(syncedActivityBurn))"
    }

    enum TodayTab: String, CaseIterable, Identifiable {
        case nutrition = "Nutrition"
        case activity = "Activity"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TodayProgressBar(
                        score: displayedScore,
                        caloriesIn: history.todayCalories,
                        caloriesBurned: syncedActivityBurn,
                        isCalculating: isScoringToday
                    )
                    .cardStyle()
                    adviceSection
                    todaySection
                        .cardStyle()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .task(id: scoreInputsKey) { await refreshTodayScore() }
            .navigationTitle("Hi, \(profileStore.profile?.name ?? "there")!")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                    .accessibilityLabel("Profile")
                }
            }
            .navigationDestination(isPresented: $isShowingAdvice) {
                AdviceView(history: history, profile: profileStore.profile)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Scan Nutrition Label", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityHint("Opens the camera to scan a packaged food's nutrition label")
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            NutritionScanView(history: history)
        }
        .sheet(isPresented: $isEditingProfile) {
            NavigationStack {
                ProfileFormView(existing: profileStore.profile) { profile in
                    profileStore.profile = profile
                    isEditingProfile = false
                }
            }
        }
    }

    // MARK: - Advice

    private var canRequestAdvice: Bool {
        history.todayCounts.total > 0
    }

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isShowingAdvice = true
            } label: {
                Label("Advice Me", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        canRequestAdvice
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.accentColor, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Color(.systemGray4)),
                        in: Capsule()
                    )
                    .shadow(
                        color: canRequestAdvice ? Color.accentColor.opacity(0.35) : .clear,
                        radius: 10,
                        y: 5
                    )
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: isShowingAdvice)
            .disabled(!canRequestAdvice)
            .accessibilityHint("Opens AI advice based on today's scans and your profile")

            if !canRequestAdvice {
                Text("Scan a product first to get advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Today list

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            Picker("Category", selection: $selectedTodayTab) {
                ForEach(TodayTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ZStack {
                if selectedTodayTab == .nutrition {
                    nutritionList
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    activityList
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(.snappy(duration: 0.3), value: selectedTodayTab)
            .clipped()
        }
    }

    @ViewBuilder
    private var nutritionList: some View {
        let tops = history.todayTopNutrients
        if tops.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "fork.knife.circle")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                Text("No nutrition data yet today.\nScan a nutrition label to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(tops.enumerated()), id: \.element.field) { index, entry in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.gradient, in: Circle())
                        Text(entry.field.displayName)
                        Spacer()
                        Text(FDAReference.massText(fromDV: entry.totalDV, field: entry.field) ?? "-")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if index < tops.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activityList: some View {
        if syncedActivities.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "figure.run.circle")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                Text("No activity synced yet today.\nSync to pull in your activities.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    syncActivities()
                } label: {
                    Group {
                        if isSyncingActivities {
                            ProgressView()
                        } else {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .disabled(isSyncingActivities)
                .padding(.top, 4)
                .accessibilityHint("Syncs today's activities")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(syncedActivities.enumerated()), id: \.element.id) { index, activity in
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
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("−\(Int(activity.kcalBurned)) kcal")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if history.todayCalories > 0 {
                                let percent = min(Int(activity.kcalBurned / history.todayCalories * 100), 999)
                                Text("≈ \(percent)% of today's calories")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if index < syncedActivities.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - AI score

    /// One sentence describing today's synced activities for the LLM prompt.
    private var activitySummarySentence: String {
        guard !syncedActivities.isEmpty else {
            return " The user has not synced any physical activity today."
        }
        let list = syncedActivities
            .map { "\($0.name) (\($0.detail), about \(Int($0.kcalBurned)) kcal)" }
            .joined(separator: ", ")
        return " Today's synced activities: \(list), burning about \(Int(syncedActivityBurn)) kcal in total."
    }

    /// Asks OpenAIService for the daily health score based on nutrition + activity.
    /// On failure, clears `aiScore` so `displayedScore` uses the local fallback.
    @MainActor
    private func refreshTodayScore() async {
        let key = scoreInputsKey

        guard !history.todayRecords.isEmpty else {
            aiScore = nil
            scoredInputsKey = nil
            return
        }

        // Cache hit: already scored these exact inputs, so reuse it (no API call).
        if scoredInputsKey == key, aiScore != nil { return }

        isScoringToday = true
        defer { isScoringToday = false }
        do {
            let summary = history.todaySummaryPrompt + activitySummarySentence
            let result = try await OpenAIService.shared.dailyHealthScore(
                summary: summary,
                profile: profileStore.profile
            )
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.7)) {
                aiScore = result.score
            }
            scoredInputsKey = key
        } catch {
            // Leave the cache key unset so the next appearance retries.
            aiScore = nil
            scoredInputsKey = nil
        }
    }

    /// Simulates syncing activities from an external source by loading dummy data
    /// after a short delay. Replace with real HealthKit/manual logging later.
    private func syncActivities() {
        isSyncingActivities = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.snappy(duration: 0.3)) {
                syncedActivities = SuggestedActivity.daily
            }
            isSyncingActivities = false
        }
    }
}

/// Inset-grouped-style card container used by the dashboard sections.
private extension View {
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Daily balance gauge: a 0–100 score computed from nutrition intake and activity by
/// `OpenAIService.dailyHealthScore` (falling back to `ScanHistoryStore.todayScore` when
/// the network is unavailable), drawn as a fill over three fixed zones
/// (Bad 0–40, Good 40–70, Healthy 70–100). The fill grows in with a spring.
private struct TodayProgressBar: View {
    /// Nil until the first scan of the day.
    let score: Double?
    let caloriesIn: Double
    let caloriesBurned: Double
    /// True while OpenAIService is computing the score.
    var isCalculating: Bool = false

    @State private var appeared = false

    private var zone: (label: String, tint: Color) {
        switch score ?? 0 {
        case ..<40: return ("Bad", .red)
        case ..<70: return ("Good", .orange)
        default: return ("Healthy", .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.headline)
                    Text(todayDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCalculating {
                    ProgressView()
                } else if let score {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(score))")
                            .font(.system(.title2, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(zone.tint)
                        Text(zone.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(zone.tint)
                    }
                }
            }

            if score == nil {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 16)
                Text("No scans yet today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                gauge

                HStack {
                    zoneLabel("Bad", tint: .red)
                    Spacer()
                    zoneLabel("Good", tint: .orange)
                    Spacer()
                    zoneLabel("Healthy", tint: .green)
                }

//                HStack(spacing: 8) {
//                    calorieChip(icon: "flame.fill", tint: .orange, text: "\(Int(caloriesIn)) kcal in")
//                    calorieChip(icon: "figure.run", tint: .green, text: "−\(Int(caloriesBurned)) kcal activity")
//                }
            }
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var gauge: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Fixed zone track: Bad 40%, Good 30%, Healthy 30%.
                HStack(spacing: 2) {
                    Capsule().fill(.red.opacity(0.18))
                        .frame(width: geometry.size.width * 0.4)
                    Capsule().fill(.orange.opacity(0.18))
                        .frame(width: geometry.size.width * 0.3 - 2)
                    Capsule().fill(.green.opacity(0.18))
                }

                Capsule()
                    .fill(zone.tint.gradient)
                    .frame(width: appeared ? geometry.size.width * CGFloat(min(score ?? 0, 100)) / 100 : 0)
            }
        }
        .frame(height: 16)
        .animation(.spring(duration: 0.7), value: appeared)
        .animation(.spring(duration: 0.7), value: score)
    }

    private func zoneLabel(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(zone.label == label ? .bold : .regular))
            .foregroundStyle(zone.label == label ? tint : .secondary)
    }

    private func calorieChip(icon: String, tint: Color, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var todayDateText: String {
        Date.now.formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(Locale(identifier: "en_US"))
        )
    }

    private var accessibilitySummary: String {
        guard let score else { return "No scans yet today." }
        return "Today's score is \(Int(score)) out of 100, in the \(zone.label) zone. Calculated from \(Int(caloriesIn)) kilocalories in and \(Int(caloriesBurned)) kilocalories of activity."
    }
}

#Preview {
    HomeView(profileStore: UserProfileStore())
}
