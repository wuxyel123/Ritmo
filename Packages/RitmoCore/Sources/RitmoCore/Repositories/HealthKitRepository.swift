import Foundation
import HealthKit
import CoreLocation
import SwiftData

// MARK: - HealthKitRepository
/// Legge tutti i dati da Apple Health (HealthKit)
/// Disponibile su iOS e watchOS.
@MainActor
public final class HealthKitRepository: ObservableObject {

    private let store = HKHealthStore()

    @Published public var isAuthorized = false
    @Published public var authError: Error?

    public init() {}

    // MARK: - Authorization

    /// Richiede tutti i permessi necessari
    public func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }

        let readTypes: Set<HKObjectType> = [
            // Attività
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            // Corpo
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .leanBodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
            // Cuore & respiro
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            // Nutrizione
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            // Mente
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            // Sonno
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            // Allenamenti
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            // Caratteristiche (sesso → coefficienti IPF GL; nascita → age-grading)
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        ]

        var readTypesVar = readTypes
        var shareTypes: Set<HKSampleType> = [
            HKQuantityType(.dietaryWater),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType()   // to allow deleting app-owned workouts
        ]

        // Workout effort score (RPE) — iOS 18 / watchOS 11+. Read others', write ours.
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) {
            let effort = HKQuantityType(.workoutEffortScore)
            readTypesVar.insert(effort)
            shareTypes.insert(effort)
        }

        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypesVar)
            isAuthorized = true
        } catch {
            authError = error
        }
    }

    // MARK: - Water Logging

    public func writeWater(ml: Double) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.dietaryWater)
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml)
        let sample = HKQuantitySample(type: type, quantity: quantity,
                                      start: Date(), end: Date())
        try await store.save(sample)
    }

    // MARK: - Sleep Quality (App Group UserDefaults)

    private nonisolated static let appGroupID = "group.alessandrodiscalzi.com.ritmo"

    public func saveSleepQuality(_ quality: SleepQuality, for date: Date = .now) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.set(quality.rawValue, forKey: sleepQualityKey(for: date))
    }

    public func loadSleepQuality(for date: Date = .now) -> SleepQuality? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return nil }
        // `integer(forKey:)` cannot tell a missing key from a stored 0, and 0
        // has been a REAL rating (pessimo) since the scale grew to 6 levels —
        // so every unrated night was silently blended into the recovery score
        // as the worst possible rating. Read the object instead.
        guard let raw = defaults.object(forKey: sleepQualityKey(for: date)) as? Int
        else { return nil }
        return SleepQuality(rawValue: raw)
    }

    private func sleepQualityKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "sleepQuality-\(f.string(from: date))"
    }

    /// Manually reported night wake-ups (per wake date) — manual sleep has no
    /// awake stages, so this feeds the continuity part of the sleep score.
    public func saveWakeCount(_ count: Int, for date: Date = .now) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.set(count, forKey: wakeCountKey(for: date))
    }

    public func loadWakeCount(for date: Date = .now) -> Int? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return nil }
        return defaults.object(forKey: wakeCountKey(for: date)) as? Int
    }

    private func wakeCountKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "sleepWakeCount-\(f.string(from: date))"
    }

    /// How long the user typically stays awake per night-time wake-up.
    /// Drives both the awake samples written to Apple Health for manually
    /// logged nights and the continuity part of the sleep score — 3 brief
    /// wakes are not the same night as 3 half-hour ones.
    public nonisolated static let defaultAwakeMinutesPerWake: Double = 10

    public nonisolated static func averageAwakeMinutes() -> Double {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              defaults.object(forKey: "sleepAvgAwakeMinutes") != nil
        else { return defaultAwakeMinutesPerWake }
        let value = defaults.double(forKey: "sleepAvgAwakeMinutes")
        return value > 0 ? value : defaultAwakeMinutesPerWake
    }

    public nonisolated static func saveAverageAwakeMinutes(_ minutes: Double) {
        UserDefaults(suiteName: appGroupID)?
            .set(max(1, minutes), forKey: "sleepAvgAwakeMinutes")
    }

    // MARK: - Sleep Logging

    /// Marks stage samples Ritmo derived from a quality rating rather than
    /// measured. Nothing else in HealthKit distinguishes the two, and without
    /// it the app would read its own estimate back as sensor data.
    public nonisolated static let syntheticStagesMetadataKey = "RitmoEstimatedStages"

    /// True for stage samples this app derived from a quality rating.
    nonisolated static func isEstimatedStage(_ sample: HKCategorySample) -> Bool {
        sample.metadata?[syntheticStagesMetadataKey] as? Bool == true
    }

    /// Writes sleep to Apple Health: the span split into deep → REM → core in
    /// proportions taken from the quality rating, interrupted by one awake
    /// window per wake-up reported, each lasting the user's configured average
    /// (Settings → Sonno).
    ///
    /// The stage split is an ESTIMATE — nobody measured it — so every stage
    /// sample carries `syntheticStagesMetadataKey`. Apple Health shows the
    /// breakdown the user wants; Ritmo's own sleep score reads the marker and
    /// declines to score deep/REM it invented itself.
    public func writeSleep(start: Date, end: Date, quality: SleepQuality? = nil,
                           wakeCount: Int = 0) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard end > start else { throw URLError(.badServerResponse) }

        let type = HKCategoryType(.sleepAnalysis)
        let total = end.timeIntervalSince(start)

        // Asleep-phase timeline (deep → REM → core when quality is known).
        var blocks: [(value: Int, start: Date, end: Date)]
        if #available(iOS 16.0, watchOS 9.0, *), let q = quality {
            let (deepFrac, remFrac) = q.sleepStageFractions
            let t1 = start.addingTimeInterval(total * deepFrac)
            let t2 = t1.addingTimeInterval(total * remFrac)
            blocks = [
                (HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start, t1),
                (HKCategoryValueSleepAnalysis.asleepREM.rawValue,  t1, t2),
                (HKCategoryValueSleepAnalysis.asleepCore.rawValue, t2, end)
            ]
        } else {
            let value: Int
            if #available(iOS 16.0, watchOS 9.0, *) {
                value = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            } else {
                value = HKCategoryValueSleepAnalysis.inBed.rawValue
            }
            blocks = [(value, start, end)]
        }

        // Carve an awake window out of the timeline per reported wake-up:
        // wake i sits at i/(N+1) of the night, so N wakes split the sleep into
        // N+1 even stretches. Capped so each wake still has sleep around it on
        // very short nights.
        var awakeWindows: [(start: Date, end: Date)] = []
        let wakeDuration: TimeInterval = Self.averageAwakeMinutes() * 60
        let n = min(max(wakeCount, 0), Int(total / (wakeDuration * 3)))
        if n > 0 {
            for i in 1...n {
                let center = start.addingTimeInterval(total * Double(i) / Double(n + 1))
                let ws = center.addingTimeInterval(-wakeDuration / 2)
                let we = center.addingTimeInterval(wakeDuration / 2)
                awakeWindows.append((ws, we))
                var carved: [(value: Int, start: Date, end: Date)] = []
                for b in blocks {
                    if b.end <= ws || b.start >= we { carved.append(b); continue }
                    if b.start < ws { carved.append((b.value, b.start, ws)) }
                    if b.end > we { carved.append((b.value, we, b.end)) }
                }
                blocks = carved
            }
        }

        // Tag the estimated stages, but not a plain undifferentiated span:
        // that one claims nothing about architecture in the first place.
        let stagesAreEstimates = quality != nil && blocks.count > 1
        let metadata: [String: Any]? = stagesAreEstimates
            ? [Self.syntheticStagesMetadataKey: true] : nil
        for b in blocks where b.end > b.start {
            try await store.save(HKCategorySample(type: type, value: b.value,
                                                  start: b.start, end: b.end,
                                                  metadata: metadata))
        }
        for w in awakeWindows {
            try await store.save(HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.awake.rawValue,
                start: w.start, end: w.end))
        }

        if let q = quality { saveSleepQuality(q, for: start) }
    }

    /// Deletes Ritmo-written sleep samples that overlap the exact [start, end] window.
    /// Used when editing a manually registered session. Cannot remove Apple Watch samples.
    public func deleteSleepSamples(from start: Date, to end: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        try await store.deleteObjects(of: type, predicate: predicate)
    }

    /// Deletes all sleep analysis samples that Ritmo wrote for the night ending on `date`,
    /// and clears the stored quality rating. Cannot remove samples from Apple Watch or other apps.
    public func deleteSleep(for date: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let calendar = Calendar.current
        let sleepStart = calendar.date(bySettingHour: 18, minute: 0, second: 0,
                                       of: calendar.date(byAdding: .day, value: -1, to: date)!)!
        let sleepEnd   = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let predicate  = HKQuery.predicateForSamples(withStart: sleepStart, end: sleepEnd)
        try await store.deleteObjects(of: type, predicate: predicate)
        UserDefaults(suiteName: Self.appGroupID)?.removeObject(forKey: sleepQualityKey(for: date))
    }

    // MARK: - Attività Giornaliera

    public func fetchDailyActivity(for date: Date) async -> DailyActivity {
        async let steps = fetchSteps(for: date)
        async let activeKcal = fetchActiveCalories(for: date)
        async let restingKcal = fetchRestingCalories(for: date)
        async let exerciseMins = fetchExerciseMinutes(for: date)
        async let flights = fetchFlightsClimbed(for: date)
        async let distKm = fetchWalkingDistance(for: date)
        async let mindful = fetchMindfulMinutes(for: date)
        async let hr = fetchAverageHeartRate(for: date)
        async let restingHR = fetchRestingHeartRate(for: date)
        async let hrv = fetchHRV(for: date)
        async let vo2 = fetchVO2Max()
        async let spo2 = fetchSpO2()
        async let rr = fetchRespiratoryRate()

        return DailyActivity(
            date: date,
            steps: await steps,
            activeCalories: await activeKcal,
            restingCalories: await restingKcal,
            exerciseMinutes: await exerciseMins,
            flightsClimbed: await flights,
            distanceKm: await distKm,
            mindfulMinutes: await mindful,
            vo2Max: await vo2,
            heartRateAvg: await hr,
            heartRateResting: await restingHR,
            hrv: await hrv,
            spO2: await spo2,
            respiratoryRate: await rr
        )
    }

    // MARK: - Nutrizione

    public func fetchNutrition(for date: Date) async -> NutritionDay {
        async let calories = fetchNutrientSum(identifier: .dietaryEnergyConsumed, unit: .kilocalorie(), for: date)
        async let protein = fetchNutrientSum(identifier: .dietaryProtein, unit: .gram(), for: date)
        async let carbs = fetchNutrientSum(identifier: .dietaryCarbohydrates, unit: .gram(), for: date)
        async let fat = fetchNutrientSum(identifier: .dietaryFatTotal, unit: .gram(), for: date)
        async let fiber = fetchNutrientSum(identifier: .dietaryFiber, unit: .gram(), for: date)
        async let water = fetchNutrientSum(identifier: .dietaryWater, unit: .liter(), for: date)

        return NutritionDay(
            date: date,
            calories: await calories,
            protein: await protein,
            carbs: await carbs,
            fat: await fat,
            fiber: await fiber,
            waterMl: await water * 1000 // litri → ml
        )
    }

    /// Nutrizione degli ultimi N giorni
    public func fetchNutritionHistory(days: Int) async -> [NutritionDay] {
        await withTaskGroup(of: NutritionDay.self) { group in
            for i in 0..<days {
                if let date = Calendar.current.date(byAdding: .day, value: -i, to: .now) {
                    group.addTask { await self.fetchNutrition(for: date) }
                }
            }
            var results: [NutritionDay] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.date > $1.date }
        }
    }

    // MARK: - Metriche Corpo

    public func fetchLatestBodyMetric() async -> BodyMetric? {
        async let weight = fetchLatestQuantity(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        async let fat = fetchLatestQuantity(identifier: .bodyFatPercentage, unit: .percent())
        async let bmi = fetchLatestQuantity(identifier: .bodyMassIndex, unit: .count())
        async let lean = fetchLatestQuantity(identifier: .leanBodyMass, unit: .gramUnit(with: .kilo))

        let w = await weight
        let f = await fat
        let b = await bmi
        let l = await lean

        guard w != nil || f != nil else { return nil }

        return BodyMetric(
            date: .now,
            weightKg: w,
            bodyFatPercentage: f.map { $0 * 100 },
            bmi: b,
            leanBodyMassKg: l
        )
    }

    public func fetchBodyWeightHistory(days: Int) async -> [BodyMetric] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { sample in
            BodyMetric(
                date: sample.startDate,
                weightKg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            )
        }
    }

    // MARK: - Sonno

    public func fetchSleep(for date: Date, includeConsistency: Bool = false) async -> SleepSession? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        // Cerca il sonno della notte precedente (dalle 18:00 del giorno prima alle 12:00 del giorno corrente)
        let calendar = Calendar.current
        let sleepStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: date)!)!
        let sleepEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let predicate = HKQuery.predicateForSamples(withStart: sleepStart, end: sleepEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }

        let stages = samples.compactMap { sample -> SleepStage? in
            guard let stageType = sleepStageType(from: sample.value) else { return nil }
            return SleepStage(startTime: sample.startDate, endTime: sample.endDate, type: stageType,
                              isEstimated: Self.isEstimatedStage(sample))
        }

        let start = samples.first!.startDate
        let end   = samples.last!.endDate
        var deviation: Double? = nil
        if includeConsistency {
            let history = await fetchRecentBedtimes(before: date)
            deviation = bedtimeDeviation(start, against: history)
        }
        return SleepSession(startTime: start, endTime: end, stages: stages,
                            bedtimeDeviationMinutes: deviation,
                            manualWakeCount: loadWakeCount(for: end),
                            manualAwakeMinutesPerWake: Self.averageAwakeMinutes())
    }

    /// Most-recent sleep session within the last `withinDays` days.
    /// Queries samples sorted by endDate desc and groups the latest cluster
    /// into a single night — avoids day-window mismatches when HealthKit
    /// sync is delayed.
    public func fetchLatestSleep(withinDays days: Int = 14) async -> SleepSession? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 400
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }

        // Latest wake time is the most recent sample's endDate
        let wakeTime = samples[0].endDate
        // Collect everything from the same night: up to 18 h before wake
        let nightStart = wakeTime.addingTimeInterval(-18 * 3600)
        let nightSamples = samples
            .filter { $0.endDate <= wakeTime && $0.startDate >= nightStart }
            .sorted { $0.startDate < $1.startDate }

        guard !nightSamples.isEmpty else { return nil }
        let stages = nightSamples.compactMap { s -> SleepStage? in
            guard let t = sleepStageType(from: s.value) else { return nil }
            return SleepStage(startTime: s.startDate, endTime: s.endDate, type: t,
                              isEstimated: Self.isEstimatedStage(s))
        }
        let history  = await fetchRecentBedtimes(before: wakeTime)
        let deviation = bedtimeDeviation(nightSamples.first!.startDate, against: history)
        return SleepSession(startTime: nightSamples.first!.startDate,
                            endTime: nightSamples.last!.endDate,
                            stages: stages,
                            bedtimeDeviationMinutes: deviation,
                            manualWakeCount: loadWakeCount(for: nightSamples.last!.endDate),
                            manualAwakeMinutesPerWake: Self.averageAwakeMinutes())
    }

    // MARK: - Allenamenti da HealthKit

    public func fetchWorkouts(days: Int) async -> [HKWorkout] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    // MARK: - Snapshot per Widget e Watch

    /// Fetch snapshot per oggi (o la data specificata)
    public func fetchDailySnapshot(for date: Date = .now, goals: UserGoals) async -> DailySnapshot {
        async let activity = fetchDailyActivity(for: date)
        async let nutrition = fetchNutrition(for: date)
        async let sleep = fetchSleep(for: date, includeConsistency: true)
        async let workouts = fetchWorkoutsOn(date: date)

        let a = await activity
        let n = await nutrition
        let s = await sleep
        let w = await workouts

        let sleepHours = s?.totalHours ?? 0
        let sleepScore = s?.qualityScore ?? 0
        let hasWorkout = !w.isEmpty
        let manualQuality = loadSleepQuality(for: date)

        // ── Score composito migliorato (0-100) ──────────────────────────────
        //
        // MOVIMENTO (0-40): sempre disponibile con iPhone/Watch
        let stepProgress   = a.stepsProgress(goal: goals.dailySteps)
        let activeProgress = min(a.activeCalories / max(goals.dailyActiveCalories, 1), 1.0)
        let movementScore  = (stepProgress * 0.5 + activeProgress * 0.5) * 40
        //
        // RECUPERO (0-30): blended da dati oggettivi HK + qualità soggettiva
        let recoveryScore: Double
        if let session = s {
            let objective = Double(session.qualityScore) / 100.0 * 30
            if let q = manualQuality {
                recoveryScore = objective * 0.6 + q.baseRecoveryScore * 0.4
            } else {
                recoveryScore = objective
            }
        } else if let q = manualQuality {
            recoveryScore = q.baseRecoveryScore
        } else {
            recoveryScore = 15
        }
        //
        // NUTRIZIONE (0-20): solo se l'utente ha loggato cibo tramite un food tracker → Apple Salute
        //   se non tracciata → 10 neutro, non penalizza
        let nutritionScore: Double
        if n.calories > 50 {
            // Calories: two-sided adherence, full within ±5% of goal, → 0 at ±50%
            // off (over-eating kills it too). Protein: floored — full credit from
            // 7.5% below goal upward (no penalty for extra protein), → 0 at half
            // the goal. Calories gate the score; protein modulates 60–100% of it.
            let calAdherence  = NutritionScale.adherence(value: n.calories, goal: goals.dailyCalories)
            let protAdherence = NutritionScale.flooredAdherence(value: n.protein, goal: goals.dailyProteinG)
            nutritionScore = calAdherence * (0.6 + 0.4 * protAdherence) * 20
        } else {
            nutritionScore = 10
        }
        //
        // ALLENAMENTO (0-10): bonus per chi si allena, o per chi raggiunge i passi (rest day intenzionale)
        let workoutBonus: Double = (hasWorkout || stepProgress >= 1.0) ? 10 : stepProgress * 10
        //
        let dayScore = min(Int(movementScore + recoveryScore + nutritionScore + workoutBonus), 100)

        return DailySnapshot(
            date: date,
            calories: n.calories,
            calorieGoal: goals.dailyCalories,
            protein: n.protein,
            proteinGoal: goals.dailyProteinG,
            carbs: n.carbs,
            carbsGoal: goals.dailyCarbsG,
            fat: n.fat,
            fatGoal: goals.dailyFatG,
            fiber: n.fiber,
            fiberGoal: goals.dailyFiberG,
            waterMl: n.waterMl,
            waterGoal: goals.dailyWaterMl,
            steps: a.steps,
            stepGoal: goals.dailySteps,
            distanceKm: a.distanceKm,
            flightsClimbed: a.flightsClimbed,
            activeCalories: a.activeCalories,
            activeCalorieGoal: goals.dailyActiveCalories,
            sleepHours: sleepHours,
            sleepScore: sleepScore,
            dayScore: dayScore,
            hasWorkedOutToday: hasWorkout,
            movementScore: movementScore,
            recoveryScore: recoveryScore,
            nutritionScore: nutritionScore,
            workoutBonus: workoutBonus
        )
    }

    /// Allenamenti HK in un giorno specifico. Filters out workouts the user
    /// removed in-app: "remove from app" leaves the workout in HealthKit, so
    /// without this filter the day score / "worked out today" flag would keep
    /// counting a deleted workout (the exclusion set is synced to the watch,
    /// so both devices agree).
    public func fetchWorkoutsOn(date: Date) async -> [HKWorkout] {
        let (start, end) = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let excluded = excludedWorkoutUUIDs()
        let all = (try? await descriptor.result(for: store)) ?? []
        return all.filter { !excluded.contains($0.uuid.uuidString) }
    }

    // MARK: - Recovery (sleep + heart)

    /// Sleep-weighted recovery readiness using last night's sleep quality plus
    /// today's HRV / resting HR against a 28-day baseline.
    public func fetchRecovery(for date: Date = .now) async -> RecoveryScore {
        async let sleepResult   = fetchLatestSleep()
        async let activityResult = fetchDailyActivity(for: date)
        async let hrvHistResult  = fetchHRVHistory(days: 28)
        async let rhrHistResult  = fetchRHRHistory(days: 28)

        let sleep    = await sleepResult
        let activity = await activityResult
        let hrvHist  = await hrvHistResult
        let rhrHist  = await rhrHistResult

        func average(_ pts: [DateValuePoint]) -> Double? {
            guard !pts.isEmpty else { return nil }
            return pts.reduce(0) { $0 + $1.value } / Double(pts.count)
        }

        return RecoveryScore(
            sleepScore: sleep?.qualityScore ?? 0,
            hrvToday: activity.hrv,
            hrvBaseline: average(hrvHist),
            rhrToday: activity.heartRateResting,
            rhrBaseline: average(rhrHist)
        )
    }

    // MARK: - Trend storici per grafici

    public func fetchHRVHistory(days: Int) async -> [DateValuePoint] {
        await fetchDailyAverageHistory(identifier: .heartRateVariabilitySDNN,
                                       unit: .secondUnit(with: .milli), days: days)
    }

    public func fetchRHRHistory(days: Int) async -> [DateValuePoint] {
        await fetchDailyAverageHistory(identifier: .restingHeartRate,
                                       unit: HKUnit(from: "count/min"), days: days)
    }

    private func fetchDailyAverageHistory(identifier: HKQuantityTypeIdentifier,
                                           unit: HKUnit, days: Int) async -> [DateValuePoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now.addingTimeInterval(86400))
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let localStore = store

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            q.initialResultsHandler = { _, results, _ in
                guard let results else { cont.resume(returning: []); return }
                var pts: [DateValuePoint] = []
                results.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let val = stat.averageQuantity()?.doubleValue(for: unit), val > 0 {
                        pts.append(DateValuePoint(date: stat.startDate, value: val))
                    }
                }
                cont.resume(returning: pts)
            }
            localStore.execute(q)
        }
    }

    public func fetchBodyWeightHistoryPoints(days: Int) async -> [DateValuePoint] {
        let metrics = await fetchBodyWeightHistory(days: days)
        return metrics.compactMap { m in m.weightKg.map { DateValuePoint(date: m.date, value: $0) } }
    }

    /// Biological sex from the Health profile — picks the IPF GL coefficient
    /// set. nil when unset/denied (callers fall back to male coefficients).
    public func isFemale() -> Bool? {
        guard let sex = try? store.biologicalSex().biologicalSex else { return nil }
        switch sex {
        case .female: return true
        case .male:   return false
        default:      return nil
        }
    }

    /// Age in whole years at `date`, from the Health profile's birth date —
    /// the age-grading input. nil when unset/denied.
    public func ageYears(at date: Date = .now) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: date).year
    }

    public func fetchBodyFatHistoryPoints(days: Int) async -> [DateValuePoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return [] }
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { DateValuePoint(date: $0.startDate, value: $0.quantity.doubleValue(for: .percent()) * 100) }
    }

    // MARK: - Importa allenamenti da Apple Health in SwiftData

    private nonisolated static let excludedWorkoutsKey = "excludedWorkoutUUIDs"

    /// HealthKit-workout UUIDs the user removed in-app, so import never re-adds them.
    /// Static + nonisolated so the watch's WatchConnectivity receiver can apply an
    /// iPhone deletion (only touches UserDefaults).
    public nonisolated static func excludedWorkoutUUIDs() -> Set<String> {
        guard let d = UserDefaults(suiteName: appGroupID) else { return [] }
        return Set(d.stringArray(forKey: excludedWorkoutsKey) ?? [])
    }

    public nonisolated static func excludeWorkout(uuid: String) {
        guard let d = UserDefaults(suiteName: appGroupID) else { return }
        var set = Set(d.stringArray(forKey: excludedWorkoutsKey) ?? [])
        set.insert(uuid)
        d.set(Array(set), forKey: excludedWorkoutsKey)
    }

    /// Replaces the whole excluded set (used when the watch receives the iPhone's set).
    public nonisolated static func replaceExcludedWorkoutUUIDs(_ uuids: [String]) {
        guard let d = UserDefaults(suiteName: appGroupID) else { return }
        d.set(uuids, forKey: excludedWorkoutsKey)
    }

    public func excludedWorkoutUUIDs() -> Set<String> { Self.excludedWorkoutUUIDs() }

    private nonisolated static let trainingLoadKey = "trainingLoadFromPhone"
    private nonisolated static let dailyRecommendationKey = "dailyRecommendationFromPhone"
    private nonisolated static let meetDateKey = "meetDateFromPhone"

    /// Meet date in the app group, so widgets/complications can count down.
    /// 0 clears it. On the watch it arrives via WatchConnectivity.
    public nonisolated static func cacheMeetDate(_ epoch: Double) {
        guard let d = UserDefaults(suiteName: appGroupID) else { return }
        if epoch > 0 { d.set(epoch, forKey: meetDateKey) }
        else { d.removeObject(forKey: meetDateKey) }
    }

    public nonisolated static func cachedMeetDate() -> Date? {
        guard let d = UserDefaults(suiteName: appGroupID) else { return nil }
        let epoch = d.double(forKey: meetDateKey)
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    /// Caches the iPhone-computed daily recommendation, same rationale as the
    /// training load below: the watch's local store can differ (no Hevy
    /// standalones, import timing), so recomputing there gives a DIFFERENT
    /// verdict. Consumers must check `computedOn` — it's day-specific.
    public nonisolated static func cacheDailyRecommendation(_ data: Data) {
        guard let d = UserDefaults(suiteName: appGroupID) else { return }
        d.set(data, forKey: dailyRecommendationKey)
    }

    public nonisolated static func cachedDailyRecommendation() -> DailyRecommendation? {
        guard let d = UserDefaults(suiteName: appGroupID),
              let data = d.data(forKey: dailyRecommendationKey) else { return nil }
        return try? JSONDecoder().decode(DailyRecommendation.self, from: data)
    }

    /// Caches the iPhone-computed TrainingLoad so the Watch can show the SAME
    /// number instead of recomputing from its own local HealthKit import —
    /// the two could otherwise diverge (different dedup timing, etc). The
    /// iPhone is the source of truth; the Watch falls back to a local compute
    /// only if it has never received one.
    public nonisolated static func cacheTrainingLoad(_ data: Data) {
        guard let d = UserDefaults(suiteName: appGroupID) else { return }
        d.set(data, forKey: trainingLoadKey)
    }

    public nonisolated static func cachedTrainingLoad() -> TrainingLoad? {
        guard let d = UserDefaults(suiteName: appGroupID),
              let data = d.data(forKey: trainingLoadKey) else { return nil }
        return try? JSONDecoder().decode(TrainingLoad.self, from: data)
    }

    /// Removes a workout from the app: records the UUID as excluded (so import won't
    /// re-add it) and drops the local copy.
    @MainActor
    public func deleteWorkout(_ session: WorkoutSession, in modelContext: ModelContext) {
        if session.source == .healthKit, let uuid = session.hkWorkoutUUID {
            Self.excludeWorkout(uuid: uuid)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }

    /// Attempts to delete the underlying workout from Apple Health. Only succeeds
    /// for app-owned workouts — Apple Watch/other-app workouts can't be deleted by us.
    public func deleteHealthKitWorkout(uuid: String) async -> Bool {
        guard let workout = await fetchWorkout(uuid: uuid) else { return false }
        do {
            try await store.delete(workout)
            return true
        } catch {
            authError = error
            return false
        }
    }

    /// Catches auto-detected + manually started entries for the same session,
    /// which HealthKit gives different UUIDs — so UUID-only dedup misses them.
    /// Shared with the Hevy merge (`workoutRangesOverlapSignificantly`).
    private func overlapsSignificantly(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        workoutRangesOverlapSignificantly(aStart, aEnd, bStart, bEnd)
    }

    /// True if `a` should be kept over `b` when both represent the same workout:
    /// prefer whichever already has a user-set RPE, then the longer, then the
    /// one with more calories (a richer/more complete record).
    private func preferred(_ a: WorkoutSession, over b: WorkoutSession) -> Bool {
        if a.hasUserRPE != b.hasUserRPE { return a.hasUserRPE }
        let aDur = a.endTime.timeIntervalSince(a.startTime)
        let bDur = b.endTime.timeIntervalSince(b.startTime)
        if aDur != bDur { return aDur > bDur }
        return a.activeCalories >= b.activeCalories
    }

    /// Returns how many NEW sessions were inserted from HealthKit — the
    /// signal callers use to trigger the Hevy enrichment (a workout arriving
    /// from Health is the only moment worth asking Hevy's API for its data).
    @discardableResult
    public func importHealthKitWorkouts(into modelContext: ModelContext) async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let windowDays = 90
        let hkWorkouts = await fetchWorkouts(days: windowDays)
        // Don't reconcile on an empty fetch — could be a transient/unauthorized read.
        guard !hkWorkouts.isEmpty else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now) ?? .distantPast

        let excluded = excludedWorkoutUUIDs()
        let currentUUIDs = Set(hkWorkouts.map { $0.uuid.uuidString })

        let allExisting = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var changed = false
        var insertedCount = 0
        var removed = Set<PersistentIdentifier>()

        // Reflect deletions: drop local HK sessions (within window) that are no
        // longer in HealthKit, or that the user removed in-app.
        for s in allExisting where s.source == .healthKit {
            guard let uuid = s.hkWorkoutUUID else { continue }
            let goneFromHealth = s.startTime >= cutoff && !currentUUIDs.contains(uuid)
            if goneFromHealth || excluded.contains(uuid) {
                modelContext.delete(s)
                removed.insert(s.persistentModelID)
                changed = true
            }
        }

        // Clean up existing local duplicates (e.g. from before this fix, or from
        // HealthKit ever having offered two overlapping entries): keep the
        // richer session of each overlapping pair, drop the rest.
        let survivors = allExisting
            .filter { !removed.contains($0.persistentModelID) && $0.source == .healthKit }
            .sorted { $0.startTime < $1.startTime }
        for i in 0..<survivors.count {
            let a = survivors[i]
            if removed.contains(a.persistentModelID) { continue }
            for j in (i + 1)..<survivors.count {
                let b = survivors[j]
                if removed.contains(b.persistentModelID) { continue }
                guard overlapsSignificantly(a.startTime, a.endTime, b.startTime, b.endTime) else { continue }
                if preferred(a, over: b) {
                    modelContext.delete(b)
                    removed.insert(b.persistentModelID)
                } else {
                    modelContext.delete(a)
                    removed.insert(a.persistentModelID)
                    break
                }
            }
        }
        // Heal Hevy/HealthKit duplicate pairs: earlier sync orders could leave
        // both a standalone .hevy session (from the API) and a .healthKit one
        // (Hevy also writes every workout to Apple Health). The Health record
        // is canonical — it carries the HK UUID (deletions, exclusions, rings)
        // plus calories — so it absorbs the API data and the extra row goes.
        let hevyStandalones = allExisting.filter {
            !removed.contains($0.persistentModelID) && $0.source == .hevy
        }
        let healthTwins = allExisting.filter {
            !removed.contains($0.persistentModelID) && $0.source == .healthKit
        }
        for hevySession in hevyStandalones {
            guard let twin = healthTwins.first(where: {
                !removed.contains($0.persistentModelID) &&
                overlapsSignificantly($0.startTime, $0.endTime,
                                      hevySession.startTime, hevySession.endTime)
            }) else { continue }
            if twin.hevyID == nil { twin.hevyID = hevySession.hevyID }
            twin.title = hevySession.title
            if twin.sourceAppName == nil { twin.sourceAppName = "Hevy" }
            if twin.sets.isEmpty {
                let orphanSets = hevySession.sets
                for set in orphanSets { set.session = twin }
            }
            modelContext.delete(hevySession)
            removed.insert(hevySession.persistentModelID)
        }
        if !removed.isEmpty { changed = true }

        var existingByUUID: [String: WorkoutSession] = [:]
        var acceptedRanges: [(start: Date, end: Date)] = []
        // ALL surviving local sessions count here, not just imported ones:
        // manual sessions carrying a hkWorkoutUUID are app-authored workouts we
        // saved to HealthKit ourselves (never re-import those), and manual
        // sessions without one still block overlapping imports — e.g. the user
        // hand-logged what the watch also recorded.
        for s in allExisting where !removed.contains(s.persistentModelID) {
            if let uuid = s.hkWorkoutUUID { existingByUUID[uuid] = s }
            acceptedRanges.append((s.startTime, s.endTime))
        }

        // Workouts recent enough to bother reading their RPE (the load window).
        let rpeCutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .distantPast

        // Longest-first so that if HealthKit hands us two overlapping NEW
        // workouts (first-time import), we keep the more complete one and
        // skip inserting the overlapping duplicate.
        for hkWorkout in hkWorkouts.sorted(by: { $0.duration > $1.duration }) {
            let uuid = hkWorkout.uuid.uuidString
            if excluded.contains(uuid) { continue }

            // Pull the user's RPE (workout effort score) from HealthKit for recent
            // workouts, so a set RPE counts toward load on every device.
            var effort: Int? = nil
            if hkWorkout.startDate >= rpeCutoff, #available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) {
                effort = await readWorkoutEffort(for: hkWorkout)
            }

            // Already imported (by UUID) → just keep its RPE in sync with HealthKit.
            if let session = existingByUUID[uuid] {
                if let e = effort, session.userRPE != e {
                    session.userRPE = e
                    changed = true
                }
                if session.sourceAppName == nil {
                    session.sourceAppName = hkWorkout.sourceRevision.source.name
                    changed = true
                }
                continue
            }

            // Same real-world session as one already accepted (different UUID,
            // overlapping time) → skip, don't create a duplicate.
            if acceptedRanges.contains(where: {
                overlapsSignificantly($0.start, $0.end, hkWorkout.startDate, hkWorkout.endDate)
            }) {
                continue
            }

            let energyType = HKQuantityType(.activeEnergyBurned)
            let distType = HKQuantityType(.distanceWalkingRunning)
            let calories = hkWorkout.statistics(for: energyType)?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
                ?? hkWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                ?? 0
            let distance = hkWorkout.statistics(for: distType)?
                .sumQuantity()?.doubleValue(for: .meter())
                ?? hkWorkout.totalDistance?.doubleValue(for: .meter())
                ?? 0

            let session = WorkoutSession(
                title: hkWorkout.workoutActivityType.ritmoActivityName,
                startTime: hkWorkout.startDate,
                endTime: hkWorkout.endDate,
                source: .healthKit,
                activeCalories: calories,
                distanceMeters: distance,
                hkActivityType: Int(hkWorkout.workoutActivityType.rawValue),
                hkWorkoutUUID: uuid,
                userRPE: effort
            )
            session.sourceAppName = hkWorkout.sourceRevision.source.name
            modelContext.insert(session)
            acceptedRanges.append((hkWorkout.startDate, hkWorkout.endDate))
            changed = true
            insertedCount += 1
        }
        if changed { try? modelContext.save() }
        return insertedCount
    }

    // MARK: - Manual workout → HealthKit

    /// Saves an app-authored (manually logged) workout to Apple Health, so it
    /// counts like any other workout: day score, rings, watch list. Returns
    /// the new HKWorkout's UUID — stored on the local session so the import
    /// pipeline recognizes it as already-present instead of duplicating it.
    /// No energy/HR samples are attached: a retrospectively logged gym session
    /// has no trustworthy calorie number, and the workout itself is the point.
    public func saveManualWorkout(start: Date, end: Date,
                                  activityType: Int = 50 /* traditionalStrengthTraining */) async -> String? {
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return nil }
        let config = HKWorkoutConfiguration()
        config.activityType = HKWorkoutActivityType(rawValue: UInt(activityType)) ?? .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            return workout?.uuid.uuidString
        } catch {
            authError = error
            return nil
        }
    }

    // MARK: - Workout effort (RPE) ↔ HealthKit

    /// Finds the HKWorkout with the given UUID string.
    private func fetchWorkout(uuid: String) async -> HKWorkout? {
        guard let id = UUID(uuidString: uuid) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: []
        )
        return (try? await descriptor.result(for: store))?.first
    }

    /// Saves the user's RPE (1–10) to Apple Health as a workout effort score and
    /// relates it to the workout, so it syncs across devices and shows in Fitness.
    public func saveWorkoutEffort(rpe: Int, forWorkoutUUID uuid: String) async {
        guard #available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) else { return }
        guard let workout = await fetchWorkout(uuid: uuid) else { return }
        await removeWorkoutEffort(for: workout)   // replace any prior value of ours
        let sample = HKQuantitySample(
            type: HKQuantityType(.workoutEffortScore),
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(min(max(rpe, 1), 10))),
            start: workout.startDate, end: workout.endDate
        )
        do {
            try await store.save(sample)
            try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
        } catch {
            authError = error
        }
    }

    /// Removes the app's stored RPE for a workout from Apple Health.
    public func removeWorkoutEffort(forWorkoutUUID uuid: String) async {
        guard #available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) else { return }
        guard let workout = await fetchWorkout(uuid: uuid) else { return }
        await removeWorkoutEffort(for: workout)
    }

    @available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *)
    private func removeWorkoutEffort(for workout: HKWorkout) async {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.workoutEffortScore),
                predicate: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil))],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else { return }
        let ours = samples.filter { $0.sourceRevision.source == HKSource.default() }
        if !ours.isEmpty { try? await store.delete(ours) }
    }

    @available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *)
    private func readWorkoutEffort(for workout: HKWorkout) async -> Int? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.workoutEffortScore),
                predicate: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)]
        )
        guard let sample = (try? await descriptor.result(for: store))?.first else { return nil }
        return Int(sample.quantity.doubleValue(for: .appleEffortScore()).rounded())
    }

    // MARK: - Workout heart rate

    public func fetchWorkoutHeartRate(start: Date, end: Date,
                                      maxHR: Double = 190) async -> WorkoutHeartRateData? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let unit = HKUnit(from: "count/min")
        let hrSamples = samples.map { HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit)) }
        return WorkoutHeartRateData(samples: hrSamples, maxHR: maxHR)
    }

    /// Highest heart rate ever recorded in the window — replaces the fixed
    /// 190 bpm assumption in the zone charts with the user's own max.
    public struct MaxHeartRate: Sendable {
        public let bpm: Double
        /// True when real readings beat the age-predicted value.
        public let isObserved: Bool
    }

    /// Age-predicted maximum, Tanaka et al. (2001): 208 − 0.7 × age.
    /// Fits measured maxima across ages far better than the old 220 − age,
    /// and — the point here — it does not require the user to ever have gone
    /// all-out. Someone who never trains near their ceiling would otherwise be
    /// handed a "max" that is merely their hardest easy day.
    public nonisolated static func predictedMaxHeartRate(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }

    /// Physiologically plausible ceiling for a wrist reading. Optical sensors
    /// spike well past this (cadence lock, cold, loose strap).
    private static let maxPlausibleHeartRate: Double = 230

    /// The highest heart rate the user actually reached, made robust to sensor
    /// spikes: daily maxima over the window, sorted, and the THIRD highest
    /// taken. One bad reading — or two — can no longer define the ceiling,
    /// while a genuine max hit repeatedly still comes through. Needs at least
    /// three days of data; below that a single unverified spike would be the
    /// whole sample, so it reports nothing instead.
    public func observedMaxHeartRate(days: Int = 365) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let calendar = Calendar.current
        let end = Date.now
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: end))
        else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteMax,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }

        let unit = HKUnit(from: "count/min")
        var dailyMaxima: [Double] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            if let bpm = stats.maximumQuantity()?.doubleValue(for: unit),
               bpm > 0, bpm <= Self.maxPlausibleHeartRate {
                dailyMaxima.append(bpm)
            }
        }
        guard dailyMaxima.count >= 3 else { return nil }
        return dailyMaxima.sorted(by: >)[2]
    }

    /// Max heart rate for the zone calculations: the age-predicted value,
    /// raised to what the user has actually hit when that is genuinely higher.
    public func fetchMaxHeartRate(days: Int = 365) async -> MaxHeartRate? {
        let predicted = ageYears().map { Self.predictedMaxHeartRate(age: $0) }
        let observed = await observedMaxHeartRate(days: days)
        switch (predicted, observed) {
        case let (predicted?, observed?):
            return observed > predicted
                ? MaxHeartRate(bpm: observed, isObserved: true)
                : MaxHeartRate(bpm: predicted, isObserved: false)
        case let (predicted?, nil):
            return MaxHeartRate(bpm: predicted, isObserved: false)
        case let (nil, observed?):
            return MaxHeartRate(bpm: observed, isObserved: true)
        default:
            return nil   // no birth date and no usable readings
        }
    }

    /// Average heart rate over an arbitrary window (bpm) — one number per
    /// run for the pace–HR model, without pulling every sample.
    public func fetchAverageHeartRate(start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let localStore = store
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .discreteAverage) { _, stats, _ in
                let bpm = stats?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                cont.resume(returning: bpm)
            }
            localStore.execute(query)
        }
    }

    /// 1-minute heart-rate recovery: bpm at the workout's end minus bpm ~60s
    /// later (the standard HRR₁ marker). Needs the watch still on the wrist
    /// after the session — returns nil when the samples aren't there or the
    /// drop isn't measurable (< 2 samples on either side).
    public func fetchHeartRateRecovery(workoutEnd end: Date) async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let windowStart = end.addingTimeInterval(-60)
        let windowEnd = end.addingTimeInterval(90)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), samples.count >= 4 else { return nil }
        let unit = HKUnit(from: "count/min")

        // Peak in the last minute of the workout vs the reading closest to +60s.
        let endWindow = samples.filter { $0.startDate <= end }
        let after = samples.filter { $0.startDate > end }
        guard let peak = endWindow.map({ $0.quantity.doubleValue(for: unit) }).max(),
              let minuteAfter = after.min(by: {
                  abs($0.startDate.timeIntervalSince(end) - 60) < abs($1.startDate.timeIntervalSince(end) - 60)
              })
        else { return nil }
        // Only meaningful when the +60s reading actually exists near the mark.
        guard abs(minuteAfter.startDate.timeIntervalSince(end) - 60) <= 30 else { return nil }
        let drop = peak - minuteAfter.quantity.doubleValue(for: unit)
        return drop > 0 ? Int(drop.rounded()) : nil
    }

    // MARK: - Workout GPS route (returns lat/lon pairs)

    /// Queries by time window — avoids the fragile predicateForObjects(from: workout) approach
    /// which doesn't reliably match HKWorkoutRoute on newer iOS versions.
    /// Returns full CLLocation objects (with timestamps) so callers can correlate with HR zones.
    public func fetchWorkoutRoute(start: Date, end: Date) async -> [CLLocation] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let timePred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let localStore = store

        let route: HKWorkoutRoute? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: timePred,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkoutRoute)
            }
            localStore.execute(q)
        }
        guard let route else { return [] }

        return await withCheckedContinuation { cont in
            var locations: [CLLocation] = []
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locs, done, _ in
                if let locs { locations.append(contentsOf: locs) }
                if done { cont.resume(returning: locations) }
            }
            localStore.execute(routeQuery)
        }
    }

    // MARK: - Days with activity (for calendar dots)

    public func fetchDaysWithActivity(in month: Date) async -> Set<String> {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(day: 1)
        let localStore = store

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, _ in
                // Built inside the handler: ISO8601DateFormatter is not
                // Sendable, so it can't be captured across the actor hop.
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate]
                var result = Set<String>()
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let sum = stat.sumQuantity(), sum.doubleValue(for: .count()) > 100 {
                        result.insert(fmt.string(from: stat.startDate))
                    }
                }
                cont.resume(returning: result)
            }
            localStore.execute(q)
        }
    }

    // MARK: - Activity history

    public func fetchActiveCaloriesHistory(days: Int) async -> [DateValuePoint] {
        await fetchDailyHistory(identifier: .activeEnergyBurned, unit: .kilocalorie(), days: days)
    }

    public func fetchStepsHistory(days: Int) async -> [DateValuePoint] {
        await fetchDailyHistory(identifier: .stepCount, unit: .count(), days: days)
    }

    private func fetchDailyHistory(identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [DateValuePoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now.addingTimeInterval(86400))
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(day: 1)
        let localStore = store

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, results, _ in
                guard let results else { cont.resume(returning: []); return }
                var pts: [DateValuePoint] = []
                results.enumerateStatistics(from: start, to: end) { stat, _ in
                    let val = stat.sumQuantity()?.doubleValue(for: unit) ?? 0
                    if val > 0 { pts.append(DateValuePoint(date: stat.startDate, value: val)) }
                }
                cont.resume(returning: pts)
            }
            localStore.execute(q)
        }
    }

    // MARK: - Private helpers

    private func fetchSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        for date: Date
    ) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let (start, end) = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let result = try? await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    /// Day total for the metrics BOTH the iPhone and the Apple Watch record
    /// (steps, distance, flights, energy). A plain sum counts the same walk
    /// twice — once per device — which is why the totals ran high compared to
    /// Apple Health, and it does merge the devices rather than add them.
    /// Bucketing the day by hour and keeping only the busiest source in each
    /// hour reproduces that: hours where both devices saw the same movement
    /// stop inflating, while an hour only one device covered still counts in
    /// full (watch on the wrist in the morning, phone in a pocket later).
    /// NOT for nutrition — two food apps logging different meals must add up.
    private func fetchMergedSourceSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        for date: Date
    ) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let (start, end) = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum, .separateBySource],
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return 0 }
        var total = 0.0
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let perSource = (stats.sources ?? []).compactMap {
                stats.sumQuantity(for: $0)?.doubleValue(for: unit)
            }
            // No per-source breakdown (single source) → the plain hour total.
            total += perSource.max() ?? stats.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        return total
    }

    private func fetchSteps(for date: Date) async -> Int {
        Int(await fetchMergedSourceSum(identifier: .stepCount, unit: .count(), for: date))
    }

    private func fetchActiveCalories(for date: Date) async -> Double {
        await fetchMergedSourceSum(identifier: .activeEnergyBurned, unit: .kilocalorie(), for: date)
    }

    private func fetchRestingCalories(for date: Date) async -> Double {
        await fetchMergedSourceSum(identifier: .basalEnergyBurned, unit: .kilocalorie(), for: date)
    }

    private func fetchExerciseMinutes(for date: Date) async -> Int {
        Int(await fetchMergedSourceSum(identifier: .appleExerciseTime, unit: .minute(), for: date))
    }

    private func fetchNutrientSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        for date: Date
    ) async -> Double {
        await fetchSum(identifier: identifier, unit: unit, for: date)
    }

    private func fetchAverageHeartRate(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let (start, end) = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try? await descriptor.result(for: store)
        return result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
    }

    private func fetchRestingHeartRate(for date: Date) async -> Double? {
        await fetchLatestQuantity(identifier: .restingHeartRate, unit: HKUnit(from: "count/min"))
    }

    private func fetchHRV(for date: Date) async -> Double? {
        await fetchLatestQuantity(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    private func fetchVO2Max() async -> Double? {
        await fetchLatestQuantity(identifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
    }

    private func fetchSpO2() async -> Double? {
        guard let v = await fetchLatestQuantity(identifier: .oxygenSaturation, unit: .percent()) else { return nil }
        return v * 100 // HealthKit returns 0-1, convert to 0-100
    }

    private func fetchRespiratoryRate() async -> Double? {
        await fetchLatestQuantity(identifier: .respiratoryRate, unit: HKUnit(from: "count/min"))
    }

    private func fetchFlightsClimbed(for date: Date) async -> Int {
        Int(await fetchMergedSourceSum(identifier: .flightsClimbed, unit: .count(), for: date))
    }

    private func fetchWalkingDistance(for date: Date) async -> Double {
        await fetchMergedSourceSum(identifier: .distanceWalkingRunning,
                                   unit: .meterUnit(with: .kilo), for: date)
    }

    private func fetchMindfulMinutes(for date: Date) async -> Int {
        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return 0 }
        let (start, end) = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else { return 0 }
        let totalSeconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return Int(totalSeconds / 60)
    }

    private func fetchLatestQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let result = try? await descriptor.result(for: store)
        return result?.first?.quantity.doubleValue(for: unit)
    }

    private func dayRange(for date: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    private func sleepStageType(from value: Int) -> SleepStageType? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake: return .awake
        case .asleepREM: return .rem
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .inBed: return nil
        default: return .unspecified
        }
    }

    /// All distinct sleep sessions for the night of `date` (18:00 prev day → 12:00 date).
    /// Consecutive samples with a gap ≤ 30 min are merged into one session.
    public func fetchAllSleepSessions(for date: Date) async -> [SleepSession] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar = Calendar.current
        let sleepStart = calendar.date(bySettingHour: 18, minute: 0, second: 0,
                                       of: calendar.date(byAdding: .day, value: -1, to: date)!)!
        let sleepEnd   = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let predicate  = HKQuery.predicateForSamples(withStart: sleepStart, end: sleepEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return [] }

        let history = await fetchRecentBedtimes(before: date)

        var sessions: [SleepSession] = []
        var group: [HKCategorySample] = [samples[0]]
        var groupEnd = samples[0].endDate

        for i in 1..<samples.count {
            let s = samples[i]
            if s.startDate.timeIntervalSince(groupEnd) > 30 * 60 {
                let dev = bedtimeDeviation(group.first!.startDate, against: history)
                sessions.append(buildSleepSession(from: group, bedtimeDeviation: dev))
                group = [s]
            } else {
                group.append(s)
            }
            groupEnd = max(groupEnd, s.endDate)
        }
        let dev = bedtimeDeviation(group.first!.startDate, against: history)
        sessions.append(buildSleepSession(from: group, bedtimeDeviation: dev))
        return sessions
    }

    private func buildSleepSession(from samples: [HKCategorySample], bedtimeDeviation: Double? = nil) -> SleepSession {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        let stages = sorted.compactMap { s -> SleepStage? in
            guard let t = sleepStageType(from: s.value) else { return nil }
            return SleepStage(startTime: s.startDate, endTime: s.endDate, type: t,
                              isEstimated: Self.isEstimatedStage(s))
        }
        return SleepSession(startTime: sorted.first!.startDate,
                            endTime: sorted.last!.endDate,
                            stages: stages,
                            bedtimeDeviationMinutes: bedtimeDeviation,
                            manualWakeCount: loadWakeCount(for: sorted.last!.endDate),
                            manualAwakeMinutesPerWake: Self.averageAwakeMinutes())
    }

    // MARK: - Bedtime consistency helpers

    private func fetchRecentBedtimes(before date: Date, lookbackDays: Int = 14) async -> [Date] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar   = Calendar.current
        let rangeStart = calendar.date(byAdding: .day, value: -lookbackDays, to: date)!
        let rangeEnd   = calendar.startOfDay(for: date)
        guard rangeEnd > rangeStart else { return [] }
        let predicate  = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return [] }
        // Group into nights and take the first sample of each as the bedtime
        var bedtimes: [Date] = []
        var groupEnd: Date = .distantPast
        for sample in samples {
            if sample.startDate.timeIntervalSince(groupEnd) > 4 * 3600 {
                bedtimes.append(sample.startDate)
            }
            if sample.endDate > groupEnd { groupEnd = sample.endDate }
        }
        return bedtimes
    }

    private func bedtimeDeviation(_ bedtime: Date, against history: [Date]) -> Double? {
        guard !history.isEmpty else { return nil }
        // Convert to "minutes since noon" so midnight-crossover times compare correctly
        // (e.g. 23:30 and 00:15 are 45 min apart, not 1395)
        func minutesSinceNoon(_ d: Date) -> Double {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return m < 720 ? m + 1440 : m
        }
        let target = minutesSinceNoon(bedtime)
        let avg    = history.map(minutesSinceNoon).reduce(0, +) / Double(history.count)
        var diff   = abs(target - avg)
        if diff > 720 { diff = 1440 - diff }
        return diff
    }
}

// MARK: - HKWorkoutActivityType helpers

extension HKWorkoutActivityType {
    public var ritmoActivityName: String {
        switch self {
        case .running: return "Corsa"
        case .cycling: return "Ciclismo"
        case .walking: return "Camminata"
        case .swimming: return "Nuoto"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining: return "Allenamento Pesi"
        case .functionalStrengthTraining: return "Forza Funzionale"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross Training"
        case .pilates: return "Pilates"
        case .dance: return "Danza"
        case .stairClimbing: return "Scale"
        case .elliptical: return "Ellittica"
        case .rowing: return "Canottaggio"
        case .soccer: return "Calcio"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .hiking: return "Escursionismo"
        case .boxing: return "Boxe"
        case .jumpRope: return "Salto con la Corda"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flessibilità"
        case .mindAndBody: return "Mind & Body"
        case .mixedCardio: return "Cardio Misto"
        default: return "Allenamento"
        }
    }

    public var ritmoActivitySymbol: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .walking: return "figure.walk"
        case .swimming: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "dumbbell.fill"
        case .highIntensityIntervalTraining: return "bolt.heart.fill"
        case .crossTraining: return "figure.cross.training"
        case .pilates: return "figure.pilates"
        case .dance: return "figure.dance"
        case .stairClimbing: return "figure.stair.stepper"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rowing"
        case .soccer: return "soccerball"
        case .basketball: return "basketball.fill"
        case .tennis: return "figure.tennis"
        case .golf: return "figure.golf"
        case .hiking: return "mountain.2.fill"
        case .boxing: return "figure.boxing"
        case .jumpRope: return "figure.jumprope"
        case .coreTraining: return "figure.core.training"
        case .flexibility, .mindAndBody: return "figure.mind.and.body"
        default: return "figure.mixed.cardio"
        }
    }
}
