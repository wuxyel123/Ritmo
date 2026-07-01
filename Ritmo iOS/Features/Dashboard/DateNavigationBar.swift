import SwiftUI
import RitmoCore

struct DateNavigationBar: View {
    @Binding var selectedDate: Date
    let isToday: Bool
    let onDateChanged: () -> Void
    var healthRepo: HealthKitRepository? = nil

    @Environment(\.locale) private var locale
    private let calendar = Calendar.current
    @State private var showingCalendar = false
    @State private var daysWithData: Set<String> = []

    var body: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate)!
                onDateChanged()
            } label: {
                Image(systemName: "chevron.left").font(.headline).padding(8)
            }

            Spacer()

            Button { showingCalendar = true } label: {
                VStack(spacing: 2) {
                    if isToday {
                        Text("Oggi").font(.headline.bold())
                    } else {
                        Text(selectedDate, format: .dateTime.weekday(.wide).locale(locale)).font(.headline.bold())
                        Text(selectedDate, format: .dateTime.day().month().year().locale(locale))
                            .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    Image(systemName: "calendar").font(.caption2).foregroundStyle(RitmoTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingCalendar) {
                NavigationStack {
                    FitCalendarView(selectedDate: $selectedDate, daysWithData: daysWithData) {
                        showingCalendar = false; onDateChanged()
                    }
                    .navigationTitle("Scegli giorno")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showingCalendar = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task(id: showingCalendar) {
                guard showingCalendar, let repo = healthRepo else { return }
                daysWithData = await repo.fetchDaysWithActivity(in: selectedDate)
            }

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate)!
                onDateChanged()
            } label: {
                Image(systemName: "chevron.right").font(.headline).padding(8)
            }
            .disabled(isToday).opacity(isToday ? 0.3 : 1)
        }
        .padding(.horizontal, 4)
    }
}
