import SwiftUI
import RitmoCore

struct WatchSleepView: View {
    let goals: UserGoals
    let sessions: [WorkoutSession]

    @EnvironmentObject private var vm: WatchViewModel
    @StateObject private var helper = WatchLogHelper()
    @StateObject private var healthRepo = HealthKitRepository()

    private enum ViewState { case display, hours, quality }
    @State private var viewState: ViewState = .display
    @State private var sleepHours: Double = 7.5
    @State private var usingTracked = false
    @State private var confirmingDelete = false

    // Primary session = longest; used for quality/delete actions
    private var primary: SleepSession? { vm.sleepSessions.max(by: { $0.totalHours < $1.totalHours }) }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 10) {
                    switch viewState {
                    case .display: displayContent
                    case .hours:   hoursContent
                    case .quality: qualityContent
                    }
                    Color.clear.frame(height: 36)
                }
                .padding(.horizontal, 8)
            }
            WatchToast(feedback: helper.feedback)
        }
        .task { await healthRepo.requestAuthorization() }
        .animation(.spring(duration: 0.3), value: helper.feedback?.id)
        .animation(.easeInOut(duration: 0.2), value: viewState)
        .confirmationDialog("Eliminare il sonno?", isPresented: $confirmingDelete) {
            Button("Elimina", role: .destructive) { Task { await deleteSleep() } }
        }
    }

    // MARK: Display

    @ViewBuilder
    private var displayContent: some View {
        if vm.sleepSessions.isEmpty {
            emptyState
        } else {
            ForEach(Array(vm.sleepSessions.sorted { $0.startTime < $1.startTime }.enumerated()),
                    id: \.element.id) { index, session in
                sessionCard(session, index: vm.sleepSessions.count > 1 ? index + 1 : nil)
            }

            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Elimina", systemImage: "trash")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Session card

    private func sessionCard(_ sleep: SleepSession, index: Int?) -> some View {
        VStack(spacing: 8) {
            if let i = index {
                HStack {
                    Text("Sessione \(i)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.25), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(sleep.qualityScore) / 100)
                        .stroke(watchScoreColor(sleep.qualityScore),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(sleep.qualityScore)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(watchScoreColor(sleep.qualityScore))
                        Text("/100").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 5) {
                    metricLine("😴", String(format: "%.1fh", sleep.totalHours), "totale", .blue)
                    metricLine("🌊", String(format: "%.1fh", sleep.deepSleepHours), "prof.", .indigo)
                    metricLine("💭", String(format: "%.1fh", sleep.remSleepHours), "REM", .purple)
                }
            }

            let hasStages = sleep.stages.contains { $0.type == .deep || $0.type == .rem || $0.type == .core }
            if hasStages {
                WatchSleepStageBar(session: sleep)
            }

            HStack {
                Label(sleep.startTime.formatted(date: .omitted, time: .shortened),
                      systemImage: "moon.zzz.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Label(sleep.endTime.formatted(date: .omitted, time: .shortened),
                      systemImage: "sun.horizon.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            scoreBreakdown(sleep)
                .padding(.top, 2)

            if vm.sleepSessions.count > 1 && sleep.id != vm.sleepSessions.last?.id {
                Divider().padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("😴").font(.system(size: 36))
            Text("Nessun sonno\nrilevato stanotte")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                usingTracked = false
                viewState = .hours
            } label: {
                Label("Registra sonno", systemImage: "bed.double.fill")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.indigo)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: Hours picker

    private var hoursContent: some View {
        VStack(spacing: 12) {
            WatchSectionHeader(icon: "😴", title: "Sonno")

            HStack(spacing: 16) {
                Button { sleepHours = max(3, sleepHours - 0.5) } label: {
                    Image(systemName: "minus")
                        .font(.caption.bold())
                        .frame(width: 36, height: 36)
                        .background(Color.indigo.opacity(0.2), in: Circle())
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)

                Text(String(format: "%.1fh", sleepHours))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo).frame(minWidth: 60)

                Button { sleepHours = min(12, sleepHours + 0.5) } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 36, height: 36)
                        .background(Color.indigo.opacity(0.2), in: Circle())
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button("Annulla") { viewState = .display }
                    .font(.caption2).foregroundStyle(.secondary).buttonStyle(.plain)
                Button {
                    usingTracked = false
                    viewState = .quality
                } label: {
                    Text("Continua")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.indigo.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Quality picker

    private var qualityContent: some View {
        VStack(spacing: 8) {
            Text("Com'è stato?")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(SleepQuality.allCases, id: \.rawValue) { quality in
                Button {
                    Task { await saveSleep(quality: quality) }
                } label: {
                    HStack(spacing: 8) {
                        Text(quality.emoji)
                        Text(quality.label).font(.caption.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(watchQualityColor(quality).opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(watchQualityColor(quality))
                }
                .buttonStyle(.plain)
            }

            Button("Salta") { Task { await saveSleep(quality: nil) } }
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func saveSleep(quality: SleepQuality?) async {
        await helper.log("Sonno salvato!") {
            if usingTracked, let t = primary {
                let hasDetailedStages = t.stages.contains {
                    $0.type == .core || $0.type == .deep || $0.type == .rem
                }
                if hasDetailedStages {
                    if let q = quality { healthRepo.saveSleepQuality(q) }
                } else {
                    try await healthRepo.writeSleep(start: t.startTime, end: t.endTime, quality: quality)
                }
            } else {
                let end   = Date()
                let start = end.addingTimeInterval(-sleepHours * 3600)
                try await healthRepo.writeSleep(start: start, end: end, quality: quality)
            }
        }
        viewState = .display
        usingTracked = false
        await vm.load(goals: goals)
    }

    private func deleteSleep() async {
        await helper.log("Sonno eliminato") {
            try await healthRepo.deleteSleep(for: .now)
        }
        await vm.load(goals: goals)
    }

    // MARK: Sub-views

    private func metricLine(_ emoji: String, _ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(emoji).font(.system(size: 11))
            Text(value).font(.caption.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func scoreBreakdown(_ sleep: SleepSession) -> some View {
        let total  = max(sleep.totalHours, 0.01)
        let awakeH = sleep.stages.filter { $0.type == .awake }.reduce(0.0) { $0 + $1.durationHours }
        let consScore: Int
        if let dev = sleep.bedtimeDeviationMinutes {
            consScore = Int(max(0.0, 1.0 - max(0.0, dev - 15) / 45.0) * 10)
        } else {
            consScore = 10
        }
        return VStack(spacing: 3) {
            scoreLine("Durata",     Int(min(sleep.totalHours / 8.0, 1.0) * 40),                          "/ 40")
            scoreLine("Profondo",   Int(min((sleep.deepSleepHours / total) / 0.15, 1.0) * 20),           "/ 20")
            scoreLine("REM",        Int(min((sleep.remSleepHours  / total) / 0.20, 1.0) * 20),           "/ 20")
            scoreLine("Continuità", Int(max(0.0, 1.0 - (awakeH / total) / 0.05) * 10),                  "/ 10")
            scoreLine("Regolarità", consScore,                                                             "/ 10")
        }
    }

    private func scoreLine(_ label: String, _ pts: Int, _ max: String) -> some View {
        HStack {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Text("\(pts)").font(.system(size: 9, weight: .bold))
            Text(max).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
