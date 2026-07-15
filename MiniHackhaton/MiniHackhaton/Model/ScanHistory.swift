import Foundation
import Observation

/// One saved scan: when it happened, what class it got, and the readings that were parsed.
struct ScanRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let classificationLabel: String
    /// Readings keyed by `NutrientField.rawValue`; only fields actually read off the label.
    let facts: [String: Double]

    init(scan: HealthScanResult, date: Date = .now) {
        id = UUID()
        self.date = date
        classificationLabel = scan.classification.label
        facts = scan.facts
    }
}

/// Today's scan tally per health category, feeding the dashboard progress bar.
struct TodayCounts: Equatable {
    var bad = 0
    var good = 0
    var healthy = 0

    var total: Int { bad + good + healthy }
}

/// Persists every scan in UserDefaults and derives the "today" aggregates the
/// home dashboard shows: category counts, top nutrients, and calories consumed.
@Observable
final class ScanHistoryStore {
    private static let defaultsKey = "scanHistory"

    private(set) var records: [ScanRecord] = [] {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([ScanRecord].self, from: data) {
            records = saved
        }
    }

    func add(_ record: ScanRecord) {
        records.append(record)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    var todayRecords: [ScanRecord] {
        records.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todayCounts: TodayCounts {
        todayRecords.reduce(into: TodayCounts()) { counts, record in
            switch record.classificationLabel {
            case "sehat": counts.healthy += 1
            case "cukup sehat": counts.good += 1
            default: counts.bad += 1
            }
        }
    }

    /// The three %DV nutrients accumulated highest across today's scans. Only %DV fields
    /// are ranked — they share a comparable scale, unlike raw kcal/gram readings.
    var todayTopNutrients: [(field: NutrientField, totalDV: Double)] {
        var totals: [NutrientField: Double] = [:]
        for record in todayRecords {
            for field in NutrientField.integerFields {
                if let value = record.facts[field.rawValue] {
                    totals[field, default: 0] += value
                }
            }
        }
        return totals.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    /// Total calories read off today's scanned labels; the bridge between nutrition
    /// and the activity suggestions ("this run burns X% of today's intake").
    var todayCalories: Double {
        todayRecords.compactMap { $0.facts[NutrientField.calories.rawValue] }.reduce(0, +)
    }

    /// 0–100 daily score behind the home progress bar, combining what was eaten with
    /// what the synced activities burn. Nil until the first scan of the day.
    ///
    /// Composition: 70% nutrition quality (average of per-scan class: sehat 100,
    /// cukup sehat 60, kurang sehat 20) + 30% activity coverage (how much of today's
    /// scanned calories `activityBurn` neutralizes, capped at full coverage).
    ///
    /// - Parameter activityBurn: total kcal burned by today's synced activities.
    ///   Zero before the user syncs, so the activity component contributes nothing.
    func todayScore(activityBurn: Double) -> Double? {
        let records = todayRecords
        guard !records.isEmpty else { return nil }

        let qualityPoints: [String: Double] = ["sehat": 100, "cukup sehat": 60, "kurang sehat": 20]
        let quality = records
            .map { qualityPoints[$0.classificationLabel] ?? 20 }
            .reduce(0, +) / Double(records.count)

        let coverage = todayCalories > 0
            ? min(activityBurn / todayCalories, 1)
            : 1

        return quality * 0.7 + coverage * 100 * 0.3
    }

    /// Today's data condensed into the sentence the LLM reasons over for daily advice.
    var todaySummaryPrompt: String {
        let counts = todayCounts
        var summary = "Today the user scanned \(counts.total) food products: \(counts.bad) unhealthy, \(counts.good) moderate, \(counts.healthy) healthy."
        if todayCalories > 0 {
            summary += " Total calories from scanned products is about \(Int(todayCalories)) kcal."
        }
        let tops = todayTopNutrients
        if !tops.isEmpty {
            let list = tops.map { "\($0.field.displayName) \(Int($0.totalDV))% DV" }.joined(separator: ", ")
            summary += " Highest nutrient intakes today: \(list)."
        }
        return summary
    }
}

/// Placeholder activity catalog until real tracking (HealthKit or manual logging) is
/// wired in. `kcalBurned` lets the dashboard relate each activity to today's intake.
struct SuggestedActivity: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let icon: String
    let kcalBurned: Double

    static let daily: [SuggestedActivity] = [
        SuggestedActivity(name: "Running", detail: "10k steps", icon: "figure.run", kcalBurned: 500),
        SuggestedActivity(name: "Gym", detail: "60 min strength training", icon: "dumbbell.fill", kcalBurned: 400),
        SuggestedActivity(name: "Pilates", detail: "45 min", icon: "figure.pilates", kcalBurned: 200),
    ]

    /// Combined burn of the daily activity list, used by the home score calculation.
    static var totalDailyBurn: Double {
        daily.reduce(0) { $0 + $1.kcalBurned }
    }
}
