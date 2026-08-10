import Foundation
import SwiftData

// MARK: - StravaService
//
// Imports RACE-tagged activities from the Strava API into the race log.
// Like the Hevy key, the credentials are the user's own: they register a
// personal API application on strava.com/settings/api (free) and paste the
// Client ID + Client Secret; the OAuth dance itself happens in the app via
// ASWebAuthenticationSession. Only races are imported — training activities
// already reach Ritmo through HealthKit, importing them twice would
// duplicate the store.
//
// Strava only ever shows the user their OWN activities here, which is what
// its API agreement permits; attribution ("Powered by Strava") belongs on any
// screen presenting the imported data.

public enum StravaError: LocalizedError {
    case notConnected
    case http(Int)
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return NSLocalizedString("Strava non collegato: apri Impostazioni → Strava e completa l'accesso.", comment: "")
        case .http(let code):
            return String(format: NSLocalizedString("Strava ha risposto con un errore (HTTP %@).", comment: ""), "\(code)")
        case .network(let e):
            return String(format: NSLocalizedString("Errore di rete: %@", comment: ""), e.localizedDescription)
        }
    }
}

public struct StravaTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Double       // epoch seconds

    public var isExpired: Bool { Date.now.timeIntervalSince1970 >= expiresAt - 60 }

    public init(accessToken: String, refreshToken: String, expiresAt: Double) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

public enum StravaService {

    public static let authorizeURL = "https://www.strava.com/oauth/mobile/authorize"

    /// Host of the OAuth redirect, and the exact string that must go in the
    /// Strava application's "Authorization Callback Domain" field.
    ///
    /// It used to be `localhost`, which works but is leftover development
    /// config: it claims the callback lands on the loopback interface when it
    /// is really caught by this app's URL scheme, and a callback domain of
    /// "localhost" on a shipping app invites questions during Strava's own
    /// review. The bundle identifier is a string the developer demonstrably
    /// controls and needs no DNS, since a custom scheme is matched literally.
    public static let callbackHost = "com.alessandrodiscalzi.ritmo"
    public static let urlScheme = "ritmo"
    public static var redirectURI: String { "\(urlScheme)://\(callbackHost)/strava" }

    /// Full authorization URL for ASWebAuthenticationSession.
    public static func authorizationURL(clientID: String) -> URL? {
        var components = URLComponents(string: authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:read_all"),
        ]
        return components?.url
    }

    // MARK: Tokens

    public static func exchangeCode(_ code: String, clientID: String,
                                    clientSecret: String) async throws -> StravaTokens {
        try await tokenRequest(body: [
            "client_id": clientID, "client_secret": clientSecret,
            "code": code, "grant_type": "authorization_code",
        ])
    }

    public static func refresh(_ tokens: StravaTokens, clientID: String,
                               clientSecret: String) async throws -> StravaTokens {
        try await tokenRequest(body: [
            "client_id": clientID, "client_secret": clientSecret,
            "refresh_token": tokens.refreshToken, "grant_type": "refresh_token",
        ])
    }

    private static func tokenRequest(body: [String: String]) async throws -> StravaTokens {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw StravaError.network(error) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StravaError.http(http.statusCode)
        }
        return try JSONDecoder().decode(StravaTokens.self, from: data)
    }

    // MARK: Activities

    public struct Activity: Decodable, Sendable {
        public let id: Int
        public let name: String
        public let distance: Double        // meters
        public let movingTime: Int         // seconds
        public let startDate: String       // ISO8601
        public let sportType: String       // "Run", "Ride", "Swim", "TrailRun"…
        public let workoutType: Int?       // run race = 1, ride race = 11

        enum CodingKeys: String, CodingKey {
            case id, name, distance
            case movingTime = "moving_time"
            case startDate = "start_date"
            case sportType = "sport_type"
            case workoutType = "workout_type"
        }

        public var isRace: Bool { workoutType == 1 || workoutType == 11 }

        public var raceSport: RaceSport {
            switch sportType {
            case "Run", "TrailRun", "VirtualRun": return .run
            case "Ride", "GravelRide", "MountainBikeRide", "VirtualRide": return .ride
            case "Swim", "OpenWaterSwim": return .swim
            default: return .other
            }
        }
    }

    /// Walks the athlete's activities (newest first) and returns the
    /// race-tagged ones. `after` makes the walk incremental.
    public static func fetchRaceActivities(accessToken: String,
                                           after: Date? = nil) async throws -> [Activity] {
        var races: [Activity] = []
        var page = 1
        while true {
            var components = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
            var query = [URLQueryItem(name: "per_page", value: "100"),
                         URLQueryItem(name: "page", value: "\(page)")]
            if let after {
                query.append(URLQueryItem(name: "after", value: "\(Int(after.timeIntervalSince1970))"))
            }
            components.queryItems = query
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, URLResponse)
            do { (data, response) = try await URLSession.shared.data(for: request) }
            catch { throw StravaError.network(error) }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw http.statusCode == 401 ? StravaError.notConnected : StravaError.http(http.statusCode)
            }
            let activities = try JSONDecoder().decode([Activity].self, from: data)
            races += activities.filter(\.isRace)
            if activities.count < 100 { break }
            page += 1
        }
        return races
    }

    /// Inserts new races into the log (deduped by Strava activity id).
    /// Returns how many were added.
    @MainActor
    public static func importRaces(_ activities: [Activity],
                                   into context: ModelContext) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<RaceResult>())) ?? [])
            .compactMap(\.stravaID))
        let formatter = ISO8601DateFormatter()
        var added = 0
        for activity in activities {
            let stravaID = "\(activity.id)"
            guard !existing.contains(stravaID),
                  let date = formatter.date(from: activity.startDate),
                  activity.distance > 0, activity.movingTime > 0 else { continue }
            context.insert(RaceResult(date: date,
                                      name: activity.name,
                                      sport: activity.raceSport,
                                      distanceMeters: activity.distance,
                                      durationSeconds: activity.movingTime,
                                      source: "strava",
                                      stravaID: stravaID))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}
