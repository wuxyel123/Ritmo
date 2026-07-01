import SwiftUI

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week = "7G"
    case month = "30G"
    case year = "Anno"
    var id: String { rawValue }
    var days: Int {
        switch self { case .week: 7; case .month: 30; case .year: 365 }
    }
    var chartUnit: Calendar.Component {
        switch self { case .week: .day; case .month: .day; case .year: .month }
    }
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .week:  "7 giorni"
        case .month: "30 giorni"
        case .year:  "Anno"
        }
    }
}
