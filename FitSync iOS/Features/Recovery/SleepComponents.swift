import SwiftUI
import FitSyncCore

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
    var deepH: Double { session.deepSleepHours }
    var remH: Double { session.remSleepHours }
    var coreH: Double { session.stages.filter { $0.type == .core }.reduce(0) { $0 + $1.durationHours } }
    var total: Double { max(session.totalHours, 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.indigo)
                        .frame(width: geo.size.width * CGFloat(deepH / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.purple)
                        .frame(width: geo.size.width * CGFloat(remH / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(FitSyncTheme.sleep)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                legend(.indigo, "Profondo")
                legend(.purple, "REM")
                legend(FitSyncTheme.sleep, "Core")
            }
            .font(.caption2)
        }
        .padding(.top, 4)
    }

    private func legend(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(FitSyncTheme.textSecondary)
        }
    }
}

struct SleepDetailSheet: View {
    let session: SleepSession
    @Environment(\.dismiss) private var dismiss

    var coreHours: Double {
        session.stages.filter { $0.type == .core }.reduce(0) { $0 + $1.durationHours }
    }
    var awakeHours: Double {
        session.stages.filter { $0.type == .awake }.reduce(0) { $0 + $1.durationHours }
    }
    var qualityColor: Color {
        session.qualityScore >= 75 ? .green : session.qualityScore >= 50 ? .orange : .red
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Score ring + key times
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(session.qualityScore) / 100)
                                .stroke(qualityColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(session.qualityScore)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(qualityColor)
                                Text("/ 100")
                                    .font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                            }
                        }
                        .frame(width: 90, height: 90)

                        VStack(alignment: .leading, spacing: 8) {
                            sleepTimeRow("Addormentamento", session.startTime, "moon.zzz.fill", .indigo)
                            sleepTimeRow("Sveglia", session.endTime, "sun.horizon.fill", .orange)
                            HStack(spacing: 6) {
                                Image(systemName: "clock").foregroundStyle(FitSyncTheme.sleep).font(.caption)
                                HStack(spacing: 4) {
                                    Text(String(format: "%.1f", session.totalHours))
                                    Text("ore totali")
                                }
                                .font(.subheadline.bold())
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))

                    // Stage breakdown numbers
                    FitCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fasi del sonno").font(.headline)
                            HStack(spacing: 0) {
                                stageMetric(String(format: "%.1fh", session.deepSleepHours),
                                            "Profondo", .indigo, "Restaurativo")
                                stageMetric(String(format: "%.1fh", session.remSleepHours),
                                            "REM", .purple, "Sogni / memoria")
                                stageMetric(String(format: "%.1fh", coreHours),
                                            "Core", FitSyncTheme.sleep, "Sonno leggero")
                                if awakeHours > 0 {
                                    stageMetric(String(format: "%.1fh", awakeHours),
                                                "Sveglio", .orange, "Svegliate")
                                }
                            }
                            if !session.stages.isEmpty {
                                SleepStageBar(session: session)
                            }
                        }
                    }

                    // Stage timeline
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

                    // Score explanation
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Come si calcola il punteggio", systemImage: "info.circle")
                                .font(.subheadline.bold()).foregroundStyle(FitSyncTheme.accent)
                            scoreRow("Durata (max 50 pt)",
                                     Int(min(session.totalHours / 8.0, 1.0) * 50),
                                     "Obiettivo: 8 ore di sonno")
                            scoreRow("Sonno profondo (max 30 pt)",
                                     Int(min(session.deepSleepHours / 1.5, 1.0) * 30),
                                     "Obiettivo: 1.5 ore di sonno profondo")
                            scoreRow("Sonno REM (max 20 pt)",
                                     Int(min(session.remSleepHours / 1.5, 1.0) * 20),
                                     "Obiettivo: 1.5 ore di REM")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func stageColor(_ type: SleepStageType) -> Color {
        switch type {
        case .deep: return .indigo
        case .rem: return .purple
        case .core: return FitSyncTheme.sleep
        case .awake: return .orange
        case .unspecified: return .gray
        }
    }

    @ViewBuilder
    private func sleepTimeRow(_ label: LocalizedStringKey, _ date: Date, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                Text(date, format: .dateTime.hour().minute()).font(.subheadline.bold())
            }
        }
    }

    @ViewBuilder
    private func stageMetric(_ value: String, _ label: LocalizedStringKey, _ color: Color, _ sub: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2.bold())
            Text(sub).font(.system(size: 8)).foregroundStyle(FitSyncTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func scoreRow(_ label: LocalizedStringKey, _ pts: Int, _ description: LocalizedStringKey) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.bold())
                Text(description).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
            }
            Spacer()
            Text("\(pts) pt").font(.caption.bold()).foregroundStyle(FitSyncTheme.accent)
        }
    }
}
