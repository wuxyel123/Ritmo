import SwiftUI
import SwiftData
import RitmoCore

// MARK: - iOS App Entry Point
@main
struct RitmoApp: App {
    @StateObject private var langManager = LanguageManager()
    @StateObject private var healthRepo = HealthKitRepository()
    @StateObject private var pro = ProStore.shared

    init() {
        _ = GoalsSyncService.shared  // activate WCSession early
        // Re-registers the App Shortcuts with Siri/Spotlight on every launch —
        // without this, dev builds often never surface them to Siri.
        RitmoShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(RitmoStore.container)
                .id(langManager.viewID)
                .environment(\.locale, langManager.locale)
                .environmentObject(langManager)
                .environmentObject(healthRepo)
                .environmentObject(pro)
                .task {
                    await healthRepo.requestAuthorization()
                    await pro.refresh()
                }
        }
    }
}

// MARK: - HevySyncCoordinator
//
// Completes Health-arrived workouts with Hevy's data. Hevy writes every
// workout to Apple Health, so the HealthKit import is the arrival signal:
// callers run the import FIRST and call this ONLY when it inserted something
// new. The incremental API pull (stops at the first page of already-known
// workouts, normally one request) then merges sets/title into those fresh
// HealthKit sessions instead of creating parallel copies. No throttle —
// a new workout in Health is exactly the moment to ask.
enum HevySyncCoordinator {
    @MainActor
    static func enrichNewWorkouts(into context: ModelContext) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "hevyConnected"),
              let key = defaults.string(forKey: "hevyApiKey"), !key.isEmpty else { return }

        let service = HevyService(apiKey: key)
        if (try? await service.importAll(into: context, stopWhenAllKnown: true) { _, _ in }) != nil {
            defaults.set(Date.now.timeIntervalSince1970, forKey: "hevyLastSync")
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.scenePhase) private var scenePhase
    @Query private var storedGoals: [UserGoals]
    @State private var selectedTab = 0
    @State private var morePath: [MoreDestination] = []
    @AppStorage("didShowWelcome") private var didShowWelcome = false

    private var goals: UserGoals { storedGoals.first ?? UserGoals() }

    private func pushGoals() {
        let ctx = RitmoStore.container.mainContext
        let canonical = UserGoals.canonical(in: ctx)
        try? ctx.save()
        GoalsSyncService.shared.send(canonical)
        // Meet date rides along on every push: keeps the watch complication
        // and the app-group cache in sync even after reinstalls.
        let meetEpoch = UserDefaults.standard.double(forKey: "meetDateEpoch")
        HealthKitRepository.cacheMeetDate(meetEpoch)
        GoalsSyncService.shared.sendMeetDate(meetEpoch)
    }

    /// Re-imports HealthKit workouts (deduping stale/duplicate entries); if
    /// anything NEW arrived, completes it with Hevy's sets via the API. Then
    /// pushes the exclusion set + freshly computed training load to the Watch —
    /// the iPhone is the source of truth for both, so the two devices agree.
    private func syncWorkoutsToWatch() async {
        let ctx = RitmoStore.container.mainContext
        if await healthRepo.importHealthKitWorkouts(into: ctx) > 0 {
            await HevySyncCoordinator.enrichNewWorkouts(into: ctx)
        }
        GoalsSyncService.shared.sendExcludedWorkouts(Array(HealthKitRepository.excludedWorkoutUUIDs()))
        GoalsSyncService.shared.sendTrainingLoad(recomputingFrom: ctx)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onNavigate: { navigate(to: $0) })
                .tabItem { Label("Oggi", systemImage: "house.fill") }.tag(0)

            WorkoutListView()
                .tabItem { Label("Allenamenti", systemImage: "dumbbell.fill") }.tag(1)

            NutritionView()
                .tabItem { Label("Nutrizione", systemImage: "fork.knife") }.tag(2)

            RecoveryView()
                .tabItem { Label("Recupero", systemImage: "bed.double.fill") }.tag(3)

            // Salute/Insights/Impostazioni share one themed "Altro" tab: with
            // seven top-level tabs UIKit collapses the overflow into its bare
            // system More list, which looks nothing like the rest of the app.
            MoreMenuView(path: $morePath)
                .tabItem { Label("Altro", systemImage: "ellipsis") }.tag(4)
        }
        .tint(RitmoTheme.accent)
        .sheet(isPresented: Binding(get: { !didShowWelcome },
                                    set: { if !$0 { didShowWelcome = true } })) {
            WelcomeSheet()
        }
        .task {
            // Seed (and heal) the exercise catalog before anything imports:
            // a Hevy import against an unseeded store loses muscle groups.
            ExerciseCatalog.ensureSeeded(in: RitmoStore.container.mainContext)
            pushGoals()
            await syncWorkoutsToWatch()
        }
        // Force a push whenever goals change or the app returns to the foreground.
        .onChange(of: goals.syncSignature) { _, _ in pushGoals() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                pushGoals()
                Task { await syncWorkoutsToWatch() }
            }
        }
        .onOpenURL { url in
            switch url.host {
            case "nutrition": navigate(to: 2)
            case "recovery":  navigate(to: 3)
            case "health":    navigate(to: 4)
            case "insights":  navigate(to: 5)
            case "workouts":  navigate(to: 1)
            default:          navigate(to: 0)
            }
        }
    }

    /// Historical indices 4/5/6 (Salute/Insights/Impostazioni) now live inside
    /// the Altro tab — translate them into tab 4 + a pushed destination.
    private func navigate(to index: Int) {
        switch index {
        case 4: selectedTab = 4; morePath = [.health]
        case 5: selectedTab = 4; morePath = [.insights]
        case 6: selectedTab = 4; morePath = [.settings]
        default: selectedTab = index
        }
    }
}

// MARK: - MoreMenuView (Altro tab — themed replacement for the system More list)

enum MoreDestination: Hashable {
    case health, insights, settings
}

struct MoreMenuView: View {
    @Binding var path: [MoreDestination]
    @EnvironmentObject private var pro: ProStore
    @State private var paywallFor: ProFeature?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: RitmoTheme.gap) {
                    menuRow(.health, icon: "heart.fill", color: .red,
                            title: "Salute", subtitle: "FC, HRV, peso e attività")
                    menuRow(.insights, icon: "chart.line.uptrend.xyaxis", color: RitmoTheme.accent,
                            title: "Insights", subtitle: "Correlazioni e tendenze sui tuoi dati",
                            locked: !pro.isPro, feature: .insights)
                    menuRow(.settings, icon: "gearshape.fill", color: .gray,
                            title: "Impostazioni", subtitle: "Obiettivi, integrazioni ed esportazione")
                }
                .padding(RitmoTheme.pagePadding)
            }
            .navigationTitle("Altro")
            .sheet(item: $paywallFor) { feature in PaywallView(requested: feature) }
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .health:   HealthView()
                case .insights: InsightsView()
                case .settings: SettingsTabView()
                }
            }
        }
    }

    private func menuRow(_ destination: MoreDestination, icon: String, color: Color,
                         title: String, subtitle: String,
                         locked: Bool = false, feature: ProFeature? = nil) -> some View {
        Button {
            if locked, let feature { paywallFor = feature } else { path.append(destination) }
        } label: {
            FitCard {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3).foregroundStyle(color)
                        .frame(width: 38, height: 38)
                        .background(color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(title)).font(.subheadline.bold())
                            if locked { ProBadge() }
                        }
                        Text(LocalizedStringKey(subtitle))
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WelcomeSheet (first launch — what to grant and connect)

struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Benvenuto in Ritmo").font(.largeTitle.bold())
                Text("Il tuo hub di analisi per allenamento, recupero e nutrizione.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            welcomeRow(icon: "heart.fill", color: .red,
                       title: "Apple Salute",
                       text: "Concedi i permessi: allenamenti, sonno, cuore, nutrizione e peso arrivano da lì.")
            welcomeRow(icon: "link", color: RitmoTheme.accent,
                       title: "Hevy",
                       text: "Collega la chiave API in Impostazioni: serie, pesi e ripetizioni completano gli allenamenti.")
            welcomeRow(icon: "flag.checkered", color: .orange,
                       title: "Gare",
                       text: "OpenPowerlifting e Strava (in Impostazioni) portano dentro i tuoi risultati di gara.")
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Continua")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RitmoTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        }
        .padding(28)
    }

    private func welcomeRow(icon: String, color: Color, title: String,
                            text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline.bold())
                Text(LocalizedStringKey(text))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
