import SwiftUI
import FitSyncCore

// MARK: - SleepSessionCard

struct SleepSessionCard: View {
    let session: SleepSession
    var index: Int? = nil
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void

    @State private var confirmingDelete = false
    @State private var selectedStage: SleepStage?

    private let fromWatch: Bool
    private let scoreColor: Color
    private let coreH: Double
    private let awakeH: Double

    init(session: SleepSession, index: Int? = nil, onEdit: (() -> Void)? = nil, onDelete: @escaping () -> Void) {
        self.session   = session
        self.index     = index
        self.onEdit    = onEdit
        self.onDelete  = onDelete
        fromWatch      = session.stages.contains { $0.type == .deep || $0.type == .rem || $0.type == .core }
        scoreColor     = session.qualityScore >= 75 ? .green : session.qualityScore >= 50 ? .orange : .red
        coreH          = session.stages.filter { $0.type == .core  }.reduce(0) { $0 + $1.durationHours }
        awakeH         = session.stages.filter { $0.type == .awake }.reduce(0) { $0 + $1.durationHours }
    }

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 14) {
                // Title (matches the Recupero card's internal title)
                HStack(spacing: 6) {
                    SectionHeader(title: "Sonno")
                    if let i = index {
                        Text("· Sessione \(i)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Header
                HStack {
                    Label(fromWatch ? "Apple Watch" : "Manuale",
                          systemImage: fromWatch ? "applewatch" : "pencil")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if !fromWatch, let edit = onEdit {
                        Button { edit() } label: {
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                // Score ring + times
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: CGFloat(session.qualityScore) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(session.qualityScore)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 7) {
                        timeRow("Addormentamento", session.startTime, "moon.zzz.fill", .indigo)
                        timeRow("Sveglia", session.endTime, "sun.horizon.fill", .orange)
                        HStack(spacing: 5) {
                            Image(systemName: "clock").font(.caption).foregroundStyle(FitSyncTheme.sleep)
                            Text(String(format: "%.1fh totali", session.totalHours))
                                .font(.subheadline.bold())
                        }
                    }
                    Spacer()
                }

                // Stage metrics
                HStack(spacing: 0) {
                    SleepMetric(value: String(format: "%.1fh", session.deepSleepHours), label: "Profondo", color: .indigo)
                    SleepMetric(value: String(format: "%.1fh", session.remSleepHours),  label: "REM",      color: .purple)
                    SleepMetric(value: String(format: "%.1fh", coreH),                  label: "Core",     color: .teal)
                    if awakeH > 0.05 {
                        SleepMetric(value: String(format: "%.1fh", awakeH), label: "Sveglio", color: .orange)
                    }
                }

                FitProgressBar(value: session.totalHours / 8.0, color: FitSyncTheme.sleep)

                if !session.stages.isEmpty {
                    SleepStageBar(session: session, selected: $selectedStage)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedStage = nil }
        }
        .confirmationDialog("Eliminare questa sessione di sonno?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { onDelete() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("I dati scritti da FitSync verranno rimossi da Apple Salute.")
        }
    }

    private func timeRow(_ label: LocalizedStringKey, _ date: Date, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(date, format: .dateTime.hour().minute()).font(.subheadline.bold())
            }
        }
    }
}

// MARK: - SleepQualityCard

struct SleepQualityCard: View {
    let quality: SleepQuality?
    let onQuality: (SleepQuality) -> Void

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Come hai dormito?").font(.headline)

                if let q = quality {
                    HStack(spacing: 14) {
                        Text(q.emoji).font(.system(size: 38))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.label).font(.title3.bold()).foregroundStyle(qualityColor(q))
                            Text("Qualità soggettiva · tocca per cambiare")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 6) {
                        ForEach(SleepQuality.allCases, id: \.rawValue) { sq in
                            Button { onQuality(sq) } label: {
                                VStack(spacing: 3) {
                                    Text(sq.emoji).font(.title2)
                                    Text(sq.label).font(.system(size: 9))
                                        .foregroundStyle(sq == q ? qualityColor(sq) : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(sq == q ? qualityColor(sq).opacity(0.15) : Color.secondary.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Valuta la qualità del sonno di questa notte")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(SleepQuality.allCases, id: \.rawValue) { sq in
                            Button { onQuality(sq) } label: {
                                HStack(spacing: 14) {
                                    Text(sq.emoji).font(.title2)
                                    Text(sq.label).font(.body.weight(.medium))
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .background(qualityColor(sq).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(qualityColor(sq))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shared helpers

struct SleepMetric: View {
    let value: String; let label: LocalizedStringKey; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(FitSyncTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SleepStageBar: View {
    let session: SleepSession
    @Binding var selected: SleepStage?

    private var sortedStages: [SleepStage] {
        session.stages.sorted { $0.startTime < $1.startTime }
    }
    private var totalDuration: Double {
        max(sortedStages.reduce(0) { $0 + $1.durationHours }, 0.1)
    }
    private var hasAwake: Bool { sortedStages.contains { $0.type == .awake } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Tooltip — the tapped phase, or a hint to interact.
            Group {
                if let s = selected {
                    HStack(spacing: 6) {
                        Circle().fill(stageColor(s.type)).frame(width: 8, height: 8)
                        Text(LocalizedStringKey(s.type.rawValue)).font(.caption.bold())
                        Text("\(s.startTime.formatted(.dateTime.hour().minute()))–\(s.endTime.formatted(.dateTime.hour().minute()))")
                            .foregroundStyle(.secondary)
                        Text("· \(Int((s.durationHours * 60).rounded())) min").foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    Text("Tocca o scorri la barra per l'orario di ogni fase")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)

            // Chronological hypnogram — tap/scrub to select a phase (like Apple Health).
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(sortedStages) { stage in
                        stageColor(stage.type)
                            .frame(width: geo.size.width * CGFloat(stage.durationHours / totalDuration))
                            .opacity(selected == nil || selected?.id == stage.id ? 1 : 0.35)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in selected = stage(atX: v.location.x, width: geo.size.width) }
                )
            }
            .frame(height: 18)

            // Bedtime → wake, with times on the bar.
            HStack {
                Label(session.startTime.formatted(.dateTime.hour().minute()), systemImage: "moon.zzz.fill")
                    .foregroundStyle(.indigo)
                Spacer()
                Label(session.endTime.formatted(.dateTime.hour().minute()), systemImage: "sun.horizon.fill")
                    .foregroundStyle(.orange)
            }
            .font(.caption2)

            HStack(spacing: 12) {
                legend(stageColor(.deep), "Profondo")
                legend(stageColor(.rem),  "REM")
                legend(stageColor(.core), "Core")
                if hasAwake { legend(stageColor(.awake), "Sveglio") }
            }
            .font(.caption2)
        }
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.12), value: selected?.id)
    }

    private func stage(atX x: CGFloat, width: CGFloat) -> SleepStage? {
        guard width > 0, !sortedStages.isEmpty else { return nil }
        let target = Double(max(0, min(x / width, 1))) * totalDuration
        var acc = 0.0
        for s in sortedStages {
            acc += s.durationHours
            if target <= acc { return s }
        }
        return sortedStages.last
    }

    private func legend(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(FitSyncTheme.textSecondary)
        }
    }
}

// MARK: - File-private helpers

func stageColor(_ type: SleepStageType) -> Color {
    switch type {
    case .deep:        return .indigo
    case .rem:         return .purple
    case .core:        return .teal     // distinct from deep (indigo)
    case .awake:       return .orange
    case .unspecified: return .gray
    }
}

func qualityColor(_ q: SleepQuality) -> Color {
    switch q {
    case .scarso:      return .red
    case .sufficiente: return .orange
    case .buono:       return .blue
    case .ottimo:      return .green
    }
}

// MARK: - SleepDetailSheet (kept for potential reuse)

struct SleepDetailSheet: View {
    let session: SleepSession
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var selectedStage: SleepStage?

    var coreHours:  Double { session.stages.filter { $0.type == .core  }.reduce(0) { $0 + $1.durationHours } }
    var awakeHours: Double { session.stages.filter { $0.type == .awake }.reduce(0) { $0 + $1.durationHours } }
    var scoreColor: Color  { session.qualityScore >= 75 ? .green : session.qualityScore >= 50 ? .orange : .red }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(session.qualityScore) / 100)
                                .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(session.qualityScore)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(scoreColor)
                                Text("/ 100").font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                            }
                        }
                        .frame(width: 90, height: 90)
                        VStack(alignment: .leading, spacing: 8) {
                            timeRow("Addormentamento", session.startTime, "moon.zzz.fill", .indigo)
                            timeRow("Sveglia", session.endTime, "sun.horizon.fill", .orange)
                            HStack(spacing: 6) {
                                Image(systemName: "clock").foregroundStyle(FitSyncTheme.sleep).font(.caption)
                                Text(String(format: "%.1f ore totali", session.totalHours)).font(.subheadline.bold())
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))

                    FitCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fasi del sonno").font(.headline)
                            HStack(spacing: 0) {
                                stageMetric(String(format: "%.1fh", session.deepSleepHours), "Profondo", .indigo, "Restaurativo")
                                stageMetric(String(format: "%.1fh", session.remSleepHours),  "REM",      .purple, "Sogni / memoria")
                                stageMetric(String(format: "%.1fh", coreHours),              "Core",     .teal, "Sonno leggero")
                                if awakeHours > 0 {
                                    stageMetric(String(format: "%.1fh", awakeHours), "Sveglio", .orange, "Svegliate")
                                }
                            }
                            if !session.stages.isEmpty { SleepStageBar(session: session, selected: $selectedStage) }
                        }
                    }

                    if !session.stages.isEmpty {
                        FitCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Timeline").font(.headline)
                                ForEach(session.stages.sorted { $0.startTime < $1.startTime }) { stage in
                                    HStack(spacing: 10) {
                                        Circle().fill(stageColor(stage.type)).frame(width: 8, height: 8)
                                        Text(stage.startTime, format: .dateTime.hour().minute())
                                            .font(.caption).frame(width: 44, alignment: .leading)
                                        Text(LocalizedStringKey(stage.type.rawValue)).font(.caption.bold())
                                        Spacer()
                                        Text(String(format: "%.0f min", stage.durationHours * 60))
                                            .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Dettaglio sonno")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                if onDelete != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Eliminare il sonno di questa notte?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Elimina sonno", role: .destructive) { onDelete?(); dismiss() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("I dati scritti da FitSync verranno rimossi da Apple Salute. I dati registrati da Apple Watch rimarranno invariati.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func timeRow(_ label: LocalizedStringKey, _ date: Date, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                Text(date, format: .dateTime.hour().minute()).font(.subheadline.bold())
            }
        }
    }

    private func stageMetric(_ value: String, _ label: LocalizedStringKey, _ color: Color, _ sub: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2.bold())
            Text(sub).font(.system(size: 8)).foregroundStyle(FitSyncTheme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
