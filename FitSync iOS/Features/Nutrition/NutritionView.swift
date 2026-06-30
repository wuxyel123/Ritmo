import SwiftUI
import SwiftData
import FitSyncCore

struct NutritionView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query private var storedGoals: [UserGoals]
    @StateObject private var vm = NutritionViewModel()
    @State private var period: HistoryPeriod = .week
    @State private var selectedDate = Date.now
    @State private var showWaterSheet = false

    var goals: UserGoals { storedGoals.first ?? UserGoals() }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Date navigation
                    DateNavigationBar(
                        selectedDate: $selectedDate,
                        isToday: isToday,
                        onDateChanged: { Task { await vm.loadDay(healthRepo: healthRepo, date: selectedDate) } },
                        healthRepo: healthRepo
                    )

                    // Today's macros
                    FitCard {
                        VStack(spacing: 12) {
                            HStack {
                                SectionHeader(title: isToday ? "Oggi" : selectedDate.formatted(.dateTime.day().month()))
                                Spacer()
                                if n.calories < 50 {
                                    Label("Dati da Apple Salute", systemImage: "heart.fill")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            MacroRow(emoji: "🔥", label: "Calorie",
                                     current: n.calories, goal: goals.dailyCalories,
                                     unit: "kcal", color: FitSyncTheme.calories)
                            MacroRow(emoji: "🥩", label: "Proteine",
                                     current: n.protein, goal: goals.dailyProteinG,
                                     unit: "g", color: FitSyncTheme.protein)
                            MacroRow(emoji: "🍞", label: "Carboidrati",
                                     current: n.carbs, goal: goals.dailyCarbsG,
                                     unit: "g", color: FitSyncTheme.carbs)
                            MacroRow(emoji: "🥑", label: "Grassi",
                                     current: n.fat, goal: goals.dailyFatG,
                                     unit: "g", color: FitSyncTheme.fat)
                            MacroRow(emoji: "🌾", label: "Fibre",
                                     current: n.fiber, goal: goals.dailyFiberG,
                                     unit: "g", color: FitSyncTheme.fiber)
                            HStack(spacing: 0) {
                                MacroRow(emoji: "💧", label: "Acqua",
                                         current: n.waterMl / 1000,
                                         goal: goals.dailyWaterMl / 1000,
                                         unit: "L", color: FitSyncTheme.water,
                                         fractionDigits: 1)
                                if isToday {
                                    Button { showWaterSheet = true } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(FitSyncTheme.water)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.leading, 8)
                                }
                            }
                        }
                    }

                    // Charts section
                    if !vm.history.isEmpty {
                        // Period picker
                        Picker("Periodo", selection: $period) {
                            ForEach(HistoryPeriod.allCases) { p in
                                Text(p.localizedLabel).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: period) { _, p in
                            Task { await vm.loadHistory(healthRepo: healthRepo, days: p.days) }
                        }

                        macroChart("Calorie",   \.calories,         goals.dailyCalories,    "kcal", FitSyncTheme.calories, .bar)
                        macroChart("Proteine",  \.protein,          goals.dailyProteinG,    "g",    FitSyncTheme.protein,  .line)
                        macroChart("Carboidrati", \.carbs,          goals.dailyCarbsG,      "g",    FitSyncTheme.carbs,    .bar)
                        macroChart("Grassi",    \.fat,              goals.dailyFatG,         "g",    FitSyncTheme.fat,      .line)
                        macroChart("Fibre",     \.fiber,            goals.dailyFiberG,       "g",    FitSyncTheme.fiber,    .bar)
                        macroChart("Acqua",     { $0.waterMl/1000 }, goals.dailyWaterMl/1000,"L",    FitSyncTheme.water,    .bar)
                    }

                    // Food tracker info
                    FoodTrackerInfoCard()
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Nutrizione")
            .task {
                await vm.loadDay(healthRepo: healthRepo, date: selectedDate)
                await vm.loadHistory(healthRepo: healthRepo, days: period.days)
            }
            .refreshable {
                await vm.loadDay(healthRepo: healthRepo, date: selectedDate)
                await vm.loadHistory(healthRepo: healthRepo, days: period.days)
            }
            .sheet(isPresented: $showWaterSheet) {
                WaterLogSheet { ml in
                    Task {
                        try? await healthRepo.writeWater(ml: ml)
                        await vm.loadDay(healthRepo: healthRepo, date: selectedDate)
                        await vm.loadHistory(healthRepo: healthRepo, days: period.days)
                    }
                }
            }
        }
    }

    var n: NutritionDay { vm.selectedDay }

    @ViewBuilder
    func macroChart(_ title: String, _ value: @escaping (NutritionDay) -> Double,
                    _ goal: Double, _ unit: String, _ color: Color, _ type: ChartDisplayType) -> some View {
        let pts = vm.displayHistory.map { ChartPoint(date: $0.date, value: value($0)) }
        InteractiveDateChart(title: title, points: pts, goal: goal, color: color,
                             unit: unit, chartUnit: period.chartUnit, chartType: type)
    }
}

// MARK: - FoodTrackerInfoCard

private struct FoodTrackerInfoCard: View {
    @State private var expanded = false

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Text("Come collegare il tuo food tracker")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FitSync legge i dati nutrizionali direttamente da Apple Salute. Per far apparire i tuoi pasti qui, connetti la tua app di tracciamento alimentare ad Apple Salute:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            infoStep("1", "Apri l'app del tuo food tracker preferito (es. MyFitnessPal, Cronometer, Lifesum…)")
                            infoStep("2", "Vai nelle impostazioni dell'app e cerca \"Apple Salute\" o \"HealthKit\"")
                            infoStep("3", "Attiva la sincronizzazione dei dati nutrizionali")
                            infoStep("4", "I dati appariranno automaticamente in FitSync")
                        }

                        Label("I dati rimangono privati sul tuo dispositivo", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func infoStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Color.red.opacity(0.8), in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
final class NutritionViewModel: ObservableObject {
    @Published var selectedDay: NutritionDay = NutritionDay(date: .now)
    @Published var history: [NutritionDay] = []

    var displayHistory: [NutritionDay] {
        history.filter { $0.calories > 50 }.sorted { $0.date < $1.date }
    }

    func loadDay(healthRepo: HealthKitRepository, date: Date) async {
        selectedDay = await healthRepo.fetchNutrition(for: date)
    }

    func loadHistory(healthRepo: HealthKitRepository, days: Int) async {
        history = await healthRepo.fetchNutritionHistory(days: days)
    }
}
