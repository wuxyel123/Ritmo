import Foundation
import HealthKit
import CoreLocation
import SwiftData

// MARK: - HealthKitRepository
/// Legge tutti i dati da Apple Health (HealthKit)
/// Disponibile su iOS e watchOS. Su Mac (Catalyst) i dati arrivano via CloudKit.
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
            HKSeriesType.workoutRoute()
        ]

        var readTypesVar = readTypes
        var shareTypes: Set<HKSampleType> = [
            HKQuantityType(.dietaryWater),
            HKCategoryType(.sleepAnalysis)
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

    private static let appGroupID = "group.alessandrodiscalzi.com.fitsync"

    public func saveSleepQuality(_ quality: SleepQuality, for date: Date = .now) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.set(quality.rawValue, forKey: sleepQualityKey(for: date))
    }

    public func loadSleepQuality(for date: Date = .now) -> SleepQuality? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return nil }
        let raw = defaults.integer(forKey: sleepQualityKey(for: date))
        return SleepQuality(rawValue: raw)
    }

    private func sleepQualityKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "sleepQuality-\(f.string(from: date))"
    }

    // MARK: - Sleep Logging

    /// Writes sleep to Apple Health.
    /// On iOS 16+ / watchOS 9+, when quality is specified, writes three consecutive
    /// stage samples (deep → REM → core) whose proportions reflect the quality rating,
    /// so Apple Health's sleep stages screen shows meaningful breakdown.
    /// On older OS or when quality is nil, writes a single asleepUnspecified sample.
    /// Quality is also persisted in the shared App Group for recovery score blending.
    public func writeSleep(start: Date, end: Date, quality: SleepQuality? = nil) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard end > start else { throw URLError(.badServerResponse) }

        let type = HKCategoryType(.sleepAnalysis)
        let total = end.timeIntervalSince(start)

        if #available(iOS 16.0, watchOS 9.0, *), let q = quality {
            let (deepFrac, remFrac) = q.sleepStageFractions
            let deepDuration = total * deepFrac
            let remDuration  = total * remFrac
            let t1 = start.addingTimeInterval(deepDuration)
            let t2 = t1.addingTimeInterval(remDuration)
            let samples: [HKCategorySample] = [
                HKCategorySample(type: type,
                                 value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                 start: start, end: t1),
                HKCategorySample(type: type,
                                 value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                                 start: t1, end: t2),
                HKCategorySample(type: type,
                                 value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                 start: t2, end: end),
            ]
            for s in samples { try await store.save(s) }
        } else {
            let value: Int
            if #available(iOS 16.0, watchOS 9.0, *) {
                value = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            } else {
                value = HKCategoryValueSleepAnalysis.inBed.rawValue
            }
            try await store.save(HKCategorySample(type: type, value: value, start: start, end: end))
        }

        if let q = quality { saveSleepQuality(q, for: start) }
    }

    /// Deletes FitSync-written sleep samples that overlap the exact [start, end] window.
    /// Used when editing a manually registered session. Cannot remove Apple Watch samples.
    public func deleteSleepSamples(from start: Date, to end: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        try await store.deleteObjects(of: type, predicate: predicate)
    }

    /// Deletes all sleep analysis samples that FitSync wrote for the night ending on `date`,
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
            return SleepStage(startTime: sample.startDate, endTime: sample.endDate, type: stageType)
        }

        let start = samples.first!.startDate
        let end   = samples.last!.endDate
        var deviation: Double? = nil
        if includeConsistency {
            let history = await fetchRecentBedtimes(before: date)
            deviation = bedtimeDeviation(start, against: history)
        }
        return SleepSession(startTime: start, endTime: end, stages: stages, bedtimeDeviationMinutes: deviation)
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
            return SleepStage(startTime: s.startDate, endTime: s.endDate, type: t)
        }
        let history  = await fetchRecentBedtimes(before: wakeTime)
        let deviation = bedtimeDeviation(nightSamples.first!.startDate, against: history)
        return SleepSession(startTime: nightSamples.first!.startDate,
                            endTime: nightSamples.last!.endDate,
                            stages: stages,
                            bedtimeDeviationMinutes: deviation)
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
            // Adherence: full within ±5% of goal, → 0 at ±50% off (see NutritionScale).
            // Calories gate the score (over/under-eating kills it); protein modulates 60–100%.
            let calAdherence  = NutritionScale.adherence(value: n.calories, goal: goals.dailyCalories)
            let protAdherence = NutritionScale.adherence(value: n.protein,  goal: goals.dailyProteinG)
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

    /// Allenamenti HK in un giorno specifico
    public func fetchWorkoutsOn(date: Date) async -> [HKWorkout] {
        let (start, end) = dayRange(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? await descriptor.result(for: store)) ?? []
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

    private static let excludedWorkoutsKey = "excludedWorkoutUUIDs"

    /// HealthKit-workout UUIDs the user removed in-app, so import never re-adds them.
    public func excludedWorkoutUUIDs() -> Set<String> {
        guard let d = UserDefaults(suiteName: Self.appGroupID) else { return [] }
        return Set(d.stringArray(forKey: Self.excludedWorkoutsKey) ?? [])
    }

    public func excludeWorkout(uuid: String) {
        guard let d = UserDefaults(suiteName: Self.appGroupID) else { return }
        var set = Set(d.stringArray(forKey: Self.excludedWorkoutsKey) ?? [])
        set.insert(uuid)
        d.set(Array(set), forKey: Self.excludedWorkoutsKey)
    }

    /// Removes a workout from the app. HealthKit workouts can't be deleted from
    /// the store by us (not app-owned), so we record the UUID as excluded and
    /// drop the local copy — import won't bring it back.
    @MainActor
    public func deleteWorkout(_ session: WorkoutSession, in modelContext: ModelContext) {
        if session.source == .healthKit, let uuid = session.hkWorkoutUUID {
            excludeWorkout(uuid: uuid)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }

    public func importHealthKitWorkouts(into modelContext: ModelContext) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let windowDays = 90
        let hkWorkouts = await fetchWorkouts(days: windowDays)
        // Don't reconcile on an empty fetch — could be a transient/unauthorized read.
        guard !hkWorkouts.isEmpty else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now) ?? .distantPast

        let excluded = excludedWorkoutUUIDs()
        let currentUUIDs = Set(hkWorkouts.map { $0.uuid.uuidString })

        let existing = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var existingByUUID: [String: WorkoutSession] = [:]
        for s in existing where s.source == .healthKit {
            if let uuid = s.hkWorkoutUUID { existingByUUID[uuid] = s }
        }

        // Workouts recent enough to bother reading their RPE (the load window).
        let rpeCutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .distantPast

        var changed = false

        // Reflect deletions: drop local HK sessions (within window) that are no
        // longer in HealthKit, or that the user removed in-app.
        for s in existing where s.source == .healthKit {
            guard let uuid = s.hkWorkoutUUID else { continue }
            let goneFromHealth = s.startTime >= cutoff && !currentUUIDs.contains(uuid)
            if goneFromHealth || excluded.contains(uuid) {
                modelContext.delete(s)
                changed = true
            }
        }

        for hkWorkout in hkWorkouts {
            let uuid = hkWorkout.uuid.uuidString
            if excluded.contains(uuid) { continue }

            // Pull the user's RPE (workout effort score) from HealthKit for recent
            // workouts, so a set RPE counts toward load on every device.
            var effort: Int? = nil
            if hkWorkout.startDate >= rpeCutoff, #available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) {
                effort = await readWorkoutEffort(for: hkWorkout)
            }

            // Already imported → just keep its RPE in sync with HealthKit.
            if let session = existingByUUID[uuid] {
                if let e = effort, session.userRPE != e {
                    session.userRPE = e
                    changed = true
                }
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
                title: hkWorkout.workoutActivityType.fitSyncName,
                startTime: hkWorkout.startDate,
                endTime: hkWorkout.endDate,
                source: .healthKit,
                activeCalories: calories,
                distanceMeters: distance,
                hkActivityType: Int(hkWorkout.workoutActivityType.rawValue),
                hkWorkoutUUID: uuid,
                userRPE: effort
            )
            modelContext.insert(session)
            changed = true
        }
        if changed { try? modelContext.save() }
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

    public func fetchWorkoutHeartRate(start: Date, end: Date) async -> WorkoutHeartRateData? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let unit = HKUnit(from: "count/min")
        let hrSamples = samples.map { HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit)) }
        return WorkoutHeartRateData(samples: hrSamples)
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
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, _ in
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

    private func fetchSteps(for date: Date) async -> Int {
        Int(await fetchSum(identifier: .stepCount, unit: .count(), for: date))
    }

    private func fetchActiveCalories(for date: Date) async -> Double {
        await fetchSum(identifier: .activeEnergyBurned, unit: .kilocalorie(), for: date)
    }

    private func fetchRestingCalories(for date: Date) async -> Double {
        await fetchSum(identifier: .basalEnergyBurned, unit: .kilocalorie(), for: date)
    }

    private func fetchExerciseMinutes(for date: Date) async -> Int {
        Int(await fetchSum(identifier: .appleExerciseTime, unit: .minute(), for: date))
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
        Int(await fetchSum(identifier: .flightsClimbed, unit: .count(), for: date))
    }

    private func fetchWalkingDistance(for date: Date) async -> Double {
        await fetchSum(identifier: .distanceWalkingRunning, unit: .meterUnit(with: .kilo), for: date)
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
            return SleepStage(startTime: s.startDate, endTime: s.endDate, type: t)
        }
        return SleepSession(startTime: sorted.first!.startDate,
                            endTime: sorted.last!.endDate,
                            stages: stages,
                            bedtimeDeviationMinutes: bedtimeDeviation)
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
    public var fitSyncName: String {
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

    public var fitSyncSymbol: String {
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
