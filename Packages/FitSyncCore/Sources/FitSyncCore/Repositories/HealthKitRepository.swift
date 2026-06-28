import Foundation
import HealthKit
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

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            authError = error
        }
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

    public func fetchSleep(for date: Date) async -> SleepSession? {
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
        let end = samples.last!.endDate
        return SleepSession(startTime: start, endTime: end, stages: stages)
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
    public func fetchDailySnapshot(for date: Date = .now, goals: UserGoals, hasHevyWorkout: Bool = false) async -> DailySnapshot {
        async let activity = fetchDailyActivity(for: date)
        async let nutrition = fetchNutrition(for: date)
        async let sleep = fetchSleep(for: date)
        async let workouts = fetchWorkoutsOn(date: date)

        let a = await activity
        let n = await nutrition
        let s = await sleep
        let w = await workouts

        let sleepHours = s?.totalHours ?? 0
        let sleepScore = s?.qualityScore ?? 0
        let hasWorkout = !w.isEmpty || hasHevyWorkout

        // ── Score composito migliorato (0-100) ──────────────────────────────
        //
        // MOVIMENTO (0-40): sempre disponibile con iPhone/Watch
        let stepProgress   = a.stepsProgress(goal: goals.dailySteps)
        let activeProgress = min(a.activeCalories / max(goals.dailyActiveCalories, 1), 1.0)
        let movementScore  = (stepProgress * 0.5 + activeProgress * 0.5) * 40
        //
        // RECUPERO (0-30): 15 neutro se no Apple Watch / dati sonno
        let recoveryScore: Double = s != nil ? Double(sleepScore) / 100.0 * 30 : 15
        //
        // NUTRIZIONE (0-20): solo se l'utente ha loggato cibo (es. tramite Yazio → HK)
        //   se non tracciata → 10 neutro, non penalizza
        let nutritionScore: Double
        if n.calories > 50 {
            let calProg  = min(n.calories / max(goals.dailyCalories, 1), 1.0)
            let protProg = min(n.protein  / max(goals.dailyProteinG, 1), 1.0)
            nutritionScore = (calProg * 0.4 + protProg * 0.6) * 20
        } else {
            nutritionScore = 10
        }
        //
        // ALLENAMENTO (0-10): bonus per chi si allena
        let workoutBonus: Double = hasWorkout ? 10 : 0
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

    public func importHealthKitWorkouts(into modelContext: ModelContext) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hkWorkouts = await fetchWorkouts(days: 90)
        guard !hkWorkouts.isEmpty else { return }

        let allDescriptor = FetchDescriptor<WorkoutSession>()
        let existing = (try? modelContext.fetch(allDescriptor)) ?? []
        let existingKeys = Set(
            existing
                .filter { $0.source == .healthKit }
                .map { "\($0.hkActivityType)_\(Int($0.startTime.timeIntervalSince1970 / 60))" }
        )

        var inserted = false
        for hkWorkout in hkWorkouts {
            let key = "\(hkWorkout.workoutActivityType.rawValue)_\(Int(hkWorkout.startDate.timeIntervalSince1970 / 60))"
            if existingKeys.contains(key) { continue }

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
                hkWorkoutUUID: hkWorkout.uuid.uuidString
            )
            modelContext.insert(session)
            inserted = true
        }
        if inserted { try? modelContext.save() }
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

    public func fetchWorkoutRoute(workoutUUID: String) async -> [(Double, Double)] {
        guard let uuid = UUID(uuidString: workoutUUID),
              HKHealthStore.isHealthDataAvailable() else { return [] }
        let pred = HKQuery.predicateForObjects(with: [uuid])
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate<HKWorkout>.workout(pred)],
            sortDescriptors: [],
            limit: 1
        )
        guard let workouts = try? await workoutDescriptor.result(for: store),
              let workout = workouts.first else { return [] }

        let routeType = HKSeriesType.workoutRoute()
        let routePred = HKQuery.predicateForObjects(from: workout)
        let localStore = store

        return await withCheckedContinuation { cont in
            let anchorQuery = HKAnchoredObjectQuery(
                type: routeType,
                predicate: routePred,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                guard let routes = samples as? [HKWorkoutRoute], let route = routes.first else {
                    cont.resume(returning: [])
                    return
                }
                var coords: [(Double, Double)] = []
                let routeQuery = HKWorkoutRouteQuery(route: route) { _, locs, done, _ in
                    if let locs { coords.append(contentsOf: locs.map { ($0.coordinate.latitude, $0.coordinate.longitude) }) }
                    if done { cont.resume(returning: coords) }
                }
                localStore.execute(routeQuery)
            }
            localStore.execute(anchorQuery)
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
