import SwiftUI
import FitSyncCore

struct DayScoreCard: View {
    let snapshot: DailySnapshot
    @State private var showingDetail = false

    var scoreColor: Color {
        switch snapshot.dayScore {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        Button { showingDetail = true } label: {
            FitCard {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.dayScore) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(snapshot.dayScore)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundStyle(FitSyncTheme.textSecondary)
                        }
                    }
                    .frame(width: 90, height: 90)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Score del giorno")
                            .font(.headline)
                        Text(scoreLabel(snapshot.dayScore))
                            .font(.subheadline)
                            .foregroundStyle(scoreColor)
                        Text(snapshot.hasWorkedOutToday ? "💪 Allenamento completato" : "🛋️ Giorno di riposo")
                            .font(.caption)
                            .foregroundStyle(FitSyncTheme.textSecondary)
                        Text(snapshot.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(FitSyncTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            DayScoreDetailSheet(snapshot: snapshot)
        }
    }

    private func scoreLabel(_ score: Int) -> LocalizedStringKey {
        switch score {
        case 90...: return "Giornata perfetta! 🌟"
        case 75..<90: return "Ottima giornata"
        case 60..<75: return "Buona giornata"
        case 40..<60: return "Giornata nella media"
        default: return "Puoi fare meglio"
        }
    }
}

// MARK: - Day Score Detail Sheet

struct DayScoreDetailSheet: View {
    let snapshot: DailySnapshot
    @Environment(\.dismiss) private var dismiss

    var scoreColor: Color {
        switch snapshot.dayScore {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Big ring summary
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.15), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.dayScore) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(snapshot.dayScore)")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("su 100")
                                .font(.subheadline)
                                .foregroundStyle(FitSyncTheme.textSecondary)
                        }
                    }
                    .frame(width: 160, height: 160)
                    .padding(.top, 8)

                    // Score components
                    FitCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Componenti del punteggio")
                                .font(.headline)

                            ScoreComponentRow(
                                icon: "figure.walk", label: "Movimento",
                                description: "Passi (\(snapshot.steps.formatted())) + calorie attive (\(Int(snapshot.activeCalories)) kcal)",
                                score: snapshot.movementScore, maxScore: 40, color: .orange
                            )
                            Divider()
                            ScoreComponentRow(
                                icon: "bed.double.fill", label: "Recupero",
                                description: snapshot.sleepHours > 0
                                    ? "Sonno \(String(format: "%.1f", snapshot.sleepHours))h · qualità \(snapshot.sleepScore)/100"
                                    : "Nessun dato sonno — punteggio neutro",
                                score: snapshot.recoveryScore, maxScore: 30, color: FitSyncTheme.sleep
                            )
                            Divider()
                            ScoreComponentRow(
                                icon: "fork.knife", label: "Nutrizione",
                                description: snapshot.calories > 50
                                    ? "Calorie \(Int(snapshot.calories))/\(Int(snapshot.calorieGoal)) · Proteine \(Int(snapshot.protein))/\(Int(snapshot.proteinGoal))g"
                                    : "Nessun dato nutrizionale — punteggio neutro",
                                score: snapshot.nutritionScore, maxScore: 20, color: FitSyncTheme.calories
                            )
                            Divider()
                            ScoreComponentRow(
                                icon: "dumbbell.fill", label: "Allenamento",
                                description: snapshot.hasWorkedOutToday
                                    ? "Allenamento completato oggi"
                                    : snapshot.workoutBonus >= 10
                                        ? "Passi raggiunti — riposo attivo"
                                        : "Nessun allenamento oggi",
                                score: snapshot.workoutBonus, maxScore: 10, color: FitSyncTheme.workout
                            )
                        }
                    }

                    // How it's calculated explanation
                    FitCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Come si calcola", systemImage: "info.circle")
                                .font(.subheadline.bold())
                                .foregroundStyle(FitSyncTheme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                explanationRow("Movimento (max 40 pt)", "Media pesata di passi e calorie attive rispetto agli obiettivi. Richiede solo iPhone o Apple Watch.")
                                explanationRow("Recupero (max 30 pt)", "Basato sulla qualità del sonno. Se mancano i dati sonno viene assegnato un punteggio neutro di 15 pt.")
                                explanationRow("Nutrizione (max 20 pt)", "Progressione verso obiettivo calorie (40%) e proteine (60%). Se non tracciata → 10 pt neutri.")
                                explanationRow("Allenamento (max 10 pt)", "Pieno punteggio con un allenamento, o se raggiungi l'obiettivo passi (riposo attivo intenzionale). Parziale in proporzione ai passi se nessuno dei due.")
                            }
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Score del giorno")
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

    @ViewBuilder
    private func explanationRow(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            Text(body).font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
        }
    }
}

// MARK: - Score Component Row

struct ScoreComponentRow: View {
    let icon: String
    let label: LocalizedStringKey
    let description: String
    let score: Double
    let maxScore: Double
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(score)) / \(Int(maxScore)) pt")
                        .font(.subheadline.bold())
                        .foregroundStyle(color)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                FitProgressBar(value: score / maxScore, color: color, height: 5)
            }
        }
    }
}
