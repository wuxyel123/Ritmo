import Foundation
import SwiftData

// MARK: - HevyService
//
// Imports the user's Hevy workout history via Hevy's public API
// (api.hevyapp.com, api-key auth — the user generates the key in the Hevy
// app, Pro required). This is the data HealthKit can't carry: full sets with
// weights/reps/set types/supersets. Exercises are matched BY NAME against the
// local store (the seed catalog carries the user's own Hevy vocabulary, so
// most match; unknown ones are created on the fly).
//
// Import strategy, per workout — the HealthKit record is canonical (Hevy
// writes every workout to Apple Health, and that record carries the HK UUID
// used for deletions, exclusions and rings), the API only completes it:
// - a session with the same hevyID already exists → RECONCILE: if the user
//   edited the workout in Hevy since the import (title, sets), the walk
//   corrects the local copy in place; unchanged ones are skipped. The
//   incremental mode stops before fully-known pages, so old edits are only
//   picked up by "Importa storico completo" — the full walk sees everything;
// - a time-overlapping local session exists (the one the HealthKit import
//   created) → if it has no sets, UPGRADE it in place: attach the sets,
//   adopt Hevy's title, keep its HealthKit identity; if it has sets, just
//   remember its hevyID;
// - otherwise create a new app-local session (source .hevy) — the workout
//   isn't in Apple Health (older than the import window, or Health sync
//   off). Never written back to Health: that would double-count.

public enum HevyError: LocalizedError {
    case invalidKey
    case http(Int)
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return AppLocalization.string("Chiave API non valida: controlla la chiave generata in Hevy (serve Hevy Pro).")
        case .http(let code):
            return String(format: AppLocalization.string("Hevy ha risposto con un errore (HTTP %@)."), "\(code)")
        case .network(let e):
            return String(format: AppLocalization.string("Errore di rete: %@"), e.localizedDescription)
        }
    }
}

@MainActor
public final class HevyService {

    private let apiKey: String
    private let decoder: JSONDecoder
    private let isoFormatter = ISO8601DateFormatter()

    public init(apiKey: String) {
        self.apiKey = apiKey
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: API DTOs (snake_case in transit)

    struct WorkoutsPage: Decodable {
        let page: Int
        let pageCount: Int
        let workouts: [HevyWorkout]
    }

    struct HevyWorkout: Decodable {
        let id: String
        let title: String
        let startTime: String
        let endTime: String
        let exercises: [HevyExercise]
    }

    struct HevyExercise: Decodable {
        let title: String
        let notes: String?
        let supersetId: Int?
        let sets: [HevySet]
    }

    struct HevySet: Decodable {
        let type: String?
        let weightKg: Double?
        let reps: Int?
        let distanceMeters: Double?
        let durationSeconds: Int?
        let rpe: Double?
    }

    // MARK: Fetching

    private func fetchPage(_ page: Int) async throws -> WorkoutsPage {
        var request = URLRequest(url: URL(string:
            "https://api.hevyapp.com/v1/workouts?page=\(page)&pageSize=10")!)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HevyError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 401 || http.statusCode == 403
                ? HevyError.invalidKey : HevyError.http(http.statusCode)
        }
        return try decoder.decode(WorkoutsPage.self, from: data)
    }

    // MARK: Import

    public struct ImportResult {
        public let imported: Int
        public let mergedIntoExisting: Int
        public let updated: Int
        public let skipped: Int
    }

    /// Cheap connectivity/credential check: fetches the first page.
    public func validate() async throws {
        _ = try await fetchPage(1)
    }

    // MARK: Routines

    public struct HevyRoutineDTO: Decodable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let exercises: [RoutineExercise]?

        public struct RoutineExercise: Decodable, Sendable {
            public let title: String
            public let sets: [RoutineSet]?
            public struct RoutineSet: Decodable, Sendable {}
        }

        public var exerciseCount: Int { exercises?.count ?? 0 }
        public var setCount: Int { exercises?.reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0 }
    }

    private struct RoutinesPage: Decodable {
        let page: Int
        let pageCount: Int
        let routines: [HevyRoutineDTO]
    }

    /// The user's Hevy routines (templates). Read-only: Ritmo shows when each
    /// was last performed, it doesn't edit them.
    public func fetchRoutines() async throws -> [HevyRoutineDTO] {
        var all: [HevyRoutineDTO] = []
        var page = 1
        var pageCount = 1
        while page <= pageCount {
            var request = URLRequest(url: URL(string:
                "https://api.hevyapp.com/v1/routines?page=\(page)&pageSize=10")!)
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
            request.setValue("application/json", forHTTPHeaderField: "accept")

            let (data, response): (Data, URLResponse)
            do { (data, response) = try await URLSession.shared.data(for: request) }
            catch { throw HevyError.network(error) }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw http.statusCode == 401 || http.statusCode == 403
                    ? HevyError.invalidKey : HevyError.http(http.statusCode)
            }
            let result = try decoder.decode(RoutinesPage.self, from: data)
            all += result.routines
            pageCount = result.pageCount
            page += 1
        }
        return all
    }

    /// Walks the user's Hevy history (newest first). With `stopWhenAllKnown`
    /// the walk ends at the first page made entirely of already-imported
    /// workouts — the incremental mode used by the automatic sync, which
    /// normally costs a single request.
    public func importAll(into context: ModelContext,
                          stopWhenAllKnown: Bool = false,
                          progress: @escaping (Int, Int) -> Void) async throws -> ImportResult {
        var imported = 0, merged = 0, updated = 0, skipped = 0
        var processed = 0
        var page = 1
        var pageCount = 1

        // The catalog must exist BEFORE matching titles: on a fresh install the
        // first Hevy import used to run against an empty store and file every
        // exercise under "Altro" with no muscle group.
        ExerciseCatalog.ensureSeeded(in: context)

        var localSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var exercisesByName: [String: Exercise] = [:]
        for e in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
            exercisesByName[e.name.lowercased()] = e
        }
        let knownHevyIDs = Set(localSessions.compactMap(\.hevyID))
        var sessionByHevyID: [String: WorkoutSession] = [:]
        for s in localSessions {
            if let id = s.hevyID { sessionByHevyID[id] = s }
        }

        while page <= pageCount {
            let result = try await fetchPage(page)
            pageCount = result.pageCount

            if stopWhenAllKnown,
               !result.workouts.isEmpty,
               result.workouts.allSatisfy({ knownHevyIDs.contains($0.id) }) {
                break
            }

            for workout in result.workouts {
                processed += 1
                progress(processed, pageCount * 10)

                guard let start = isoFormatter.date(from: workout.startTime)
                          ?? fallbackDate(workout.startTime),
                      let end = isoFormatter.date(from: workout.endTime)
                          ?? fallbackDate(workout.endTime),
                      end > start else {
                    skipped += 1
                    continue
                }

                // Already imported → correct the local copy if the user edited
                // the workout in Hevy since (title, sets, times).
                if let known = sessionByHevyID[workout.id] {
                    if reconcile(known, with: workout, start: start, end: end,
                                 context: context, exercisesByName: &exercisesByName) {
                        updated += 1
                    } else {
                        skipped += 1
                    }
                    continue
                }

                // Same workout already here from HealthKit? Upgrade in place.
                if let existing = localSessions.first(where: {
                    $0.hevyID == nil && overlaps($0, start: start, end: end)
                }) {
                    if existing.sets.isEmpty {
                        attach(workout.exercises, to: existing,
                               context: context, exercisesByName: &exercisesByName)
                        existing.hevyID = workout.id
                        existing.title = workout.title   // the real name, not "Allenamento"
                        if existing.sourceAppName == nil { existing.sourceAppName = "Hevy" }
                        merged += 1
                    } else {
                        existing.hevyID = workout.id   // recognized, keep richer copy
                        skipped += 1
                    }
                    continue
                }

                let session = WorkoutSession(title: workout.title,
                                             startTime: start,
                                             endTime: end,
                                             source: .hevy,
                                             hkActivityType: 50)
                session.hevyID = workout.id
                session.sourceAppName = "Hevy"
                context.insert(session)
                attach(workout.exercises, to: session,
                       context: context, exercisesByName: &exercisesByName)
                localSessions.append(session)
                imported += 1

                if imported % 25 == 0 { try? context.save() }
            }
            page += 1
        }

        try? context.save()
        return ImportResult(imported: imported, mergedIntoExisting: merged,
                            updated: updated, skipped: skipped)
    }

    // MARK: Reconciliation (edits made in Hevy after the import)

    /// Brings an already-imported session back in line with Hevy's current
    /// version. Sets are compared field-by-field and rebuilt only when they
    /// actually differ, so the full-history walk stays cheap for the (vast)
    /// majority of untouched workouts. Times are only adopted for standalone
    /// .hevy sessions — for the others Apple Health owns the clock.
    /// Returns true when something was corrected.
    private func reconcile(_ session: WorkoutSession, with workout: HevyWorkout,
                           start: Date, end: Date,
                           context: ModelContext,
                           exercisesByName: inout [String: Exercise]) -> Bool {
        var changed = false
        if session.title != workout.title {
            session.title = workout.title
            changed = true
        }
        if session.source == .hevy,
           abs(session.startTime.timeIntervalSince(start)) > 1
            || abs(session.endTime.timeIntervalSince(end)) > 1 {
            session.startTime = start
            session.endTime = end
            changed = true
        }
        if signature(of: session) != signature(of: workout.exercises) {
            for old in session.sets { context.delete(old) }
            session.sets = []
            attach(workout.exercises, to: session,
                   context: context, exercisesByName: &exercisesByName)
            changed = true
        }
        return changed
    }

    /// Order-sensitive per-set fingerprint of what `attach` would write —
    /// the two overloads must stay in lockstep with it.
    private func signature(of session: WorkoutSession) -> [String] {
        session.sets.sorted { $0.setIndex < $1.setIndex }.map { set in
            var fields: [String] = []
            fields.append(set.exercise?.name ?? "?")
            fields.append(set.setType.rawValue)
            fields.append(String(format: "%.2f", set.weightKg))
            fields.append(set.reps.map { String($0) } ?? "-")
            fields.append(set.durationSeconds.map { String($0) } ?? "-")
            fields.append(set.distanceMeters.map { String(format: "%.0f", $0) } ?? "-")
            fields.append(set.rpe.map { String(format: "%.1f", $0) } ?? "-")
            fields.append(set.exerciseNotes)
            fields.append(set.supersetId ?? "-")
            return fields.joined(separator: "|")
        }
    }

    private func signature(of exercises: [HevyExercise]) -> [String] {
        var rows: [String] = []
        for hevyExercise in exercises {
            let name = ExerciseCatalog.canonicalName(hevyExercise.title)
            let notes = hevyExercise.notes ?? ""
            let superset = hevyExercise.supersetId.map { String($0) } ?? "-"
            for hevySet in hevyExercise.sets {
                var fields: [String] = []
                fields.append(name)
                fields.append(setType(from: hevySet.type).rawValue)
                fields.append(String(format: "%.2f", hevySet.weightKg ?? 0))
                fields.append(hevySet.reps.map { String($0) } ?? "-")
                fields.append(hevySet.durationSeconds.map { String($0) } ?? "-")
                fields.append(hevySet.distanceMeters.map { String(format: "%.0f", $0) } ?? "-")
                fields.append(hevySet.rpe.map { String(format: "%.1f", $0) } ?? "-")
                fields.append(notes)
                fields.append(superset)
                rows.append(fields.joined(separator: "|"))
            }
        }
        return rows
    }

    private func overlaps(_ session: WorkoutSession, start: Date, end: Date) -> Bool {
        workoutRangesOverlapSignificantly(session.startTime, session.endTime, start, end)
    }

    private func attach(_ hevyExercises: [HevyExercise], to session: WorkoutSession,
                        context: ModelContext, exercisesByName: inout [String: Exercise]) {
        var index = 0
        for hevyExercise in hevyExercises {
            // Canonicalize known historic typos so old titles land on the
            // corrected catalog exercise.
            let name = ExerciseCatalog.canonicalName(hevyExercise.title)
            let key = name.lowercased()
            let exercise: Exercise
            if let found = exercisesByName[key] {
                exercise = found
            } else {
                exercise = Exercise(name: name, muscleGroup: .other)
                context.insert(exercise)
                exercisesByName[key] = exercise
            }
            for hevySet in hevyExercise.sets {
                let set = WorkoutSet(setIndex: index,
                                     setType: setType(from: hevySet.type),
                                     weightKg: hevySet.weightKg ?? 0,
                                     reps: hevySet.reps,
                                     durationSeconds: hevySet.durationSeconds,
                                     distanceMeters: hevySet.distanceMeters,
                                     rpe: hevySet.rpe,
                                     exerciseNotes: hevyExercise.notes ?? "",
                                     supersetId: hevyExercise.supersetId.map(String.init))
                context.insert(set)
                set.exercise = exercise
                set.session = session
                index += 1
            }
        }
    }

    private func setType(from raw: String?) -> SetType {
        switch raw {
        case "warmup":  return .warmup
        case "dropset": return .dropSet
        case "failure": return .failure
        default:        return .normal
        }
    }

    /// Hevy sometimes returns fractional-second ISO dates.
    private func fallbackDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
