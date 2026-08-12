import Foundation

// MARK: - OpenPowerliftingService
//
// Reads a lifter's meet history from openpowerlifting.org. There is no
// formal REST API — the site exposes the same CSV its "Download as CSV"
// button uses at /api/liftercsv/{username} (username = the slug in the
// lifter-page URL, e.g. openpowerlifting.org/u/johnhaack → "johnhaack").
// Read-only, no auth. Failed attempts appear as negative kg in the raw
// attempt columns; the Best3…Kg columns already resolve them.

public struct OPLMeet: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let meetName: String
    public let federation: String
    public let event: String           // "SBD" full meet, "B"/"D"/"S" single lift…
    public let equipment: String       // "Raw", "Wraps", "Single-ply"…
    public let division: String
    public let bodyweightKg: Double?
    public let weightClass: String
    public let bestSquatKg: Double?
    public let bestBenchKg: Double?
    public let bestDeadliftKg: Double?
    public let totalKg: Double?
    public let goodlift: Double?       // IPF GL points as scored by OPL
    public let dots: Double?
    public let place: String
}

public enum OPLError: LocalizedError {
    case lifterNotFound
    case http(Int)
    case network(Error)
    case emptyData

    public var errorDescription: String? {
        switch self {
        case .lifterNotFound:
            return AppLocalization.string("Atleta non trovato su OpenPowerlifting: controlla lo username (quello nell'URL della tua pagina).")
        case .http(let code):
            return String(format: AppLocalization.string("OpenPowerlifting ha risposto con un errore (HTTP %@)."), "\(code)")
        case .network(let e):
            return String(format: AppLocalization.string("Errore di rete: %@"), e.localizedDescription)
        case .emptyData:
            return AppLocalization.string("Nessuna gara trovata per questo atleta.")
        }
    }
}

public enum OpenPowerliftingService {

    /// Fetches and parses the lifter's meets, newest first.
    public static func fetchMeets(username: String) async throws -> [OPLMeet] {
        let slug = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let url = URL(string: "https://www.openpowerlifting.org/api/liftercsv/\(slug)") else {
            throw OPLError.lifterNotFound
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw OPLError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 404 ? OPLError.lifterNotFound : OPLError.http(http.statusCode)
        }
        guard let csv = String(data: data, encoding: .utf8) else { throw OPLError.emptyData }

        let meets = parse(csv: csv)
        guard !meets.isEmpty else { throw OPLError.emptyData }
        return meets.sorted { $0.date > $1.date }
    }

    // MARK: CSV parsing

    static func parse(csv: String) -> [OPLMeet] {
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard rows.count > 1 else { return [] }

        let header = splitCSVLine(rows[0])
        func index(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let dateIdx = index("Date"), let nameIdx = index("MeetName") else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        func field(_ fields: [String], _ name: String) -> String {
            index(name).flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
        }
        func number(_ fields: [String], _ name: String) -> Double? {
            Double(field(fields, name)).flatMap { $0 > 0 ? $0 : nil }
        }

        return rows.dropFirst().compactMap { row in
            let fields = splitCSVLine(row)
            guard let date = formatter.date(from: field(fields, "Date")),
                  nameIdx < fields.count else { return nil }
            return OPLMeet(date: date,
                           meetName: fields[nameIdx],
                           federation: field(fields, "Federation"),
                           event: field(fields, "Event"),
                           equipment: field(fields, "Equipment"),
                           division: field(fields, "Division"),
                           bodyweightKg: number(fields, "BodyweightKg"),
                           weightClass: field(fields, "WeightClassKg"),
                           bestSquatKg: number(fields, "Best3SquatKg"),
                           bestBenchKg: number(fields, "Best3BenchKg"),
                           bestDeadliftKg: number(fields, "Best3DeadliftKg"),
                           totalKg: number(fields, "TotalKg"),
                           goodlift: number(fields, "Goodlift"),
                           dots: number(fields, "Dots"),
                           place: field(fields, "Place"))
        }
    }

    /// Minimal quoted-field-aware CSV splitter (meet names can contain commas).
    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            switch char {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current)
                current = ""
            case "\r": break
            default: current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
