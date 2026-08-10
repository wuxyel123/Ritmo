import Foundation
import SwiftData

// MARK: - RaceResult
//
// A competition result for endurance sports — the cardio counterpart of the
// powerlifting comp maxes. Entered manually or imported from Strava
// (race-tagged activities). Kept separate from WorkoutSession on purpose:
// a race is an official RESULT (chip time, fixed distance), not a training
// log entry, and most races predate the 90-day HealthKit import window.

public enum RaceSport: String, Codable, CaseIterable {
    case run, ride, swim, triathlon, other

    public var displayName: String {
        switch self {
        case .run:       return "Corsa"
        case .ride:      return "Bici"
        case .swim:      return "Nuoto"
        case .triathlon: return "Triathlon"
        case .other:     return "Altro"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .run:       return "figure.run"
        case .ride:      return "figure.outdoor.cycle"
        case .swim:      return "figure.pool.swim"
        case .triathlon: return "medal"
        case .other:     return "flag.checkered"
        }
    }
}

@Model
public final class RaceResult {
    // Every property carries a default. The store is local-only now, so this
    // is no longer required — but defaults also keep SwiftData migrations
    // additive, which is worth having on its own.
    public var id: UUID = UUID()
    public var date: Date = Date.now
    public var name: String = ""
    public var sportRaw: String = RaceSport.run.rawValue
    public var distanceMeters: Double = 0
    public var durationSeconds: Int = 0
    public var sourceRaw: String = "manual"    // "manual" | "strava"
    public var stravaID: String?               // dedupe key for imported races

    public init(id: UUID = UUID(),
                date: Date,
                name: String,
                sport: RaceSport,
                distanceMeters: Double,
                durationSeconds: Int,
                source: String = "manual",
                stravaID: String? = nil) {
        self.id = id
        self.date = date
        self.name = name
        self.sportRaw = sport.rawValue
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.sourceRaw = source
        self.stravaID = stravaID
    }

    public var sport: RaceSport {
        get { RaceSport(rawValue: sportRaw) ?? .other }
        set { sportRaw = newValue.rawValue }
    }

    /// sec/km for runs, km/h for rides — the caller picks via `sport`.
    public var paceSecondsPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return Double(durationSeconds) / (distanceMeters / 1000)
    }

    public var speedKmH: Double {
        guard durationSeconds > 0 else { return 0 }
        return (distanceMeters / 1000) / (Double(durationSeconds) / 3600)
    }
}
