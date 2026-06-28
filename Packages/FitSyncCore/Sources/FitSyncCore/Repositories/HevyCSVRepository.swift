import Foundation
import SwiftData

// MARK: - HevyCSVRepository
/// Importa e parsa i dati esportati da Hevy in formato CSV
/// Formato Hevy: title,start_time,end_time,description,exercise_title,
///               superset_id,exercise_notes,set_index,set_type,
///               weight_lbs,reps,distance_miles,duration_seconds,rpe
public final class HevyCSVRepository {

    private let modelContext: ModelContext

    // Mapping automatico esercizio → gruppo muscolare
    // Espandibile facilmente aggiungendo nuove voci
    private static let muscleGroupMap: [String: MuscleGroup] = [
        // Petto
        "panca": .chest, "bench press": .chest, "chest": .chest,
        "pec": .chest, "croci": .chest, "fly": .chest, "dips": .chest,
        // Schiena
        "stacco": .back, "deadlift": .back, "lat": .back, "rematore": .back,
        "row": .back, "pull": .back, "trazioni": .back, "pulldown": .back,
        "cable row": .back, "schiena": .back,
        // Spalle
        "spalle": .shoulders, "shoulder": .shoulders, "press": .shoulders,
        "alzate": .shoulders, "lateral raise": .shoulders, "military": .shoulders,
        // Bicipiti
        "curl": .biceps, "bicep": .biceps, "bicipiti": .biceps, "hammer": .biceps,
        // Tricipiti
        "tricep": .triceps, "tricipiti": .triceps, "skull": .triceps,
        "pushdown": .triceps, "french": .triceps, "dip": .triceps,
        // Core
        "plank": .core, "crunch": .core, "addome": .core, "abs": .core,
        "core": .core, "russian": .core, "leg raise": .core,
        // Gambe
        "squat": .quads, "leg press": .quads, "leg extension": .quads,
        "quad": .quads, "affondi": .quads, "lunge": .quads,
        "leg curl": .hamstrings, "hamstring": .hamstrings, "femorali": .hamstrings,
        "stiff": .hamstrings, "romanian": .hamstrings,
        "glutei": .glutes, "glute": .glutes, "hip thrust": .glutes,
        "polpacci": .calves, "calf": .calves, "calves": .calves,
        // Cardio
        "corsa": .cardio, "run": .cardio, "bike": .cardio, "ciclismo": .cardio,
        "rowing": .cardio, "cardio": .cardio, "treadmill": .cardio,
        // Avambracci
        "forearm": .forearms, "avambracci": .forearms, "wrist": .forearms,
    ]

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Import da URL (Share Extension / File picker)

    /// Entry point principale — importa da URL (file CSV condiviso dalla Share Extension)
    @discardableResult
    public func importCSV(from url: URL) async throws -> ImportResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try await importCSV(content: content)
    }

    /// Importa da stringa (utile per test)
    @discardableResult
    public func importCSV(content: String) async throws -> ImportResult {
        let rows = parseCSV(content)
        guard rows.count > 1 else {
            throw ImportError.emptyFile
        }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard validateHeaders(headers) else {
            throw ImportError.invalidFormat
        }

        // Raggruppa le righe per sessione (stesso title + start_time)
        var sessionMap: [String: [CSVRow]] = [:]
        for row in rows.dropFirst() {
            guard row.count >= headers.count else { continue }
            let mapped = Dictionary(uniqueKeysWithValues: zip(headers, row))
            let key = "\(mapped["title"] ?? "")||\(mapped["start_time"] ?? "")"
            sessionMap[key, default: []].append(mapped)
        }

        var importedCount = 0
        var skippedCount = 0
        var exercises: [String: Exercise] = [:]

        for (_, rows) in sessionMap {
            guard let firstRow = rows.first else { continue }

            // Controlla se la sessione esiste già (evita duplicati)
            let startTime = parseDate(firstRow["start_time"])
            let endTime = parseDate(firstRow["end_time"])
            guard let startTime, let endTime else { skippedCount += 1; continue }

            // Verifica duplicato
            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.startTime == startTime }
            )
            if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
                skippedCount += 1
                continue
            }

            // Crea la sessione
            let session = WorkoutSession(
                title: firstRow["title"] ?? "Allenamento",
                startTime: startTime,
                endTime: endTime,
                notes: firstRow["description"] ?? "",
                source: .hevy
            )
            modelContext.insert(session)

            // Crea i set
            for row in rows {
                let exerciseName = row["exercise_title"] ?? "Esercizio"

                // Riusa o crea l'esercizio
                if exercises[exerciseName] == nil {
                    let exercise = findOrCreateExercise(name: exerciseName, exercises: &exercises)
                    exercises[exerciseName] = exercise
                }

                let set = WorkoutSet(
                    setIndex: Int(row["set_index"] ?? "0") ?? 0,
                    setType: SetType(rawValue: row["set_type"] ?? "normal") ?? .normal,
                    weightKg: lbsToKg(Double(row["weight_lbs"] ?? "") ?? 0),
                    reps: Int(row["reps"] ?? ""),
                    durationSeconds: Int(row["duration_seconds"] ?? ""),
                    distanceMeters: milesToMeters(Double(row["distance_miles"] ?? "")),
                    rpe: Double(row["rpe"] ?? ""),
                    exerciseNotes: row["exercise_notes"] ?? "",
                    supersetId: row["superset_id"]?.isEmpty == false ? row["superset_id"] : nil
                )
                set.exercise = exercises[exerciseName]
                set.session = session
                modelContext.insert(set)
            }

            importedCount += 1
        }

        try modelContext.save()
        return ImportResult(imported: importedCount, skipped: skippedCount, total: sessionMap.count)
    }

    // MARK: - Private: CSV Parsing

    private typealias CSVRow = [String: String]

    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in content {
            switch char {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    currentField.append(char)
                } else {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                }
            case "\n", "\r":
                if inQuotes {
                    currentField.append(char)
                } else if !currentRow.isEmpty || !currentField.isEmpty {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                }
            default:
                currentField.append(char)
            }
        }
        // Ultima riga
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }

    private func validateHeaders(_ headers: [String]) -> Bool {
        let required = ["title", "start_time", "exercise_title", "set_index"]
        return required.allSatisfy { headers.contains($0) }
    }

    // MARK: - Private: Helpers

    private func findOrCreateExercise(name: String, exercises: inout [String: Exercise]) -> Exercise {
        if let existing = exercises[name] { return existing }

        // Cerca nel DB prima di crearne uno nuovo
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name == name }
        )
        if let found = try? modelContext.fetch(descriptor), let exercise = found.first {
            return exercise
        }

        let muscleGroup = detectMuscleGroup(from: name)
        let exercise = Exercise(name: name, muscleGroup: muscleGroup)
        modelContext.insert(exercise)
        return exercise
    }

    private func detectMuscleGroup(from exerciseName: String) -> MuscleGroup {
        let lower = exerciseName.lowercased()
        for (keyword, group) in Self.muscleGroupMap {
            if lower.contains(keyword) { return group }
        }
        return .other
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        // Formato Hevy: "28 Mar 2025, 17:29"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.date(from: string)
    }

    private func lbsToKg(_ lbs: Double) -> Double {
        lbs * 0.453592
    }

    private func milesToMeters(_ miles: Double?) -> Double? {
        guard let miles, miles > 0 else { return nil }
        return miles * 1609.344
    }
}

// MARK: - Supporting Types

public struct ImportResult {
    public let imported: Int
    public let skipped: Int
    public let total: Int

    public var message: String {
        "\(imported) sessioni importate, \(skipped) già presenti o saltate"
    }
}

public enum ImportError: LocalizedError {
    case emptyFile
    case invalidFormat
    case saveFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyFile: return "Il file CSV è vuoto"
        case .invalidFormat: return "Formato non riconosciuto. Assicurati di esportare da Hevy (non da altre app)"
        case .saveFailed(let err): return "Errore nel salvataggio: \(err.localizedDescription)"
        }
    }
}
