import SwiftUI

struct FitCalendarView: View {
    @Binding var selectedDate: Date
    let daysWithData: Set<String>
    let onSelect: () -> Void

    @State private var displayedMonth = Date.now
    @Environment(\.locale) private var locale
    private let calendar = Calendar.current
    private let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
    }
    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)!.count
    }
    private var weekdayOfFirst: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }
    private var dayNames: [String] {
        var cal = Calendar.current
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month header
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline.bold())
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month))
            }

            // Day-of-week header
            HStack {
                ForEach(dayNames, id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(0..<weekdayOfFirst, id: \.self) { _ in Color.clear }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
                    let isFuture = date > .now
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let hasData = daysWithData.contains(fmt.string(from: date))

                    Button {
                        if !isFuture { selectedDate = date; onSelect() }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(day)")
                                .font(.subheadline.bold())
                                .frame(width: 36, height: 36)
                                .background(isSelected ? RitmoTheme.accent : Color.clear,
                                            in: Circle())
                                .foregroundStyle(isSelected ? .white : isFuture ? Color.secondary : Color.primary)
                            Circle().fill(hasData ? RitmoTheme.accent : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                }
            }

            Divider()

            // "Oggi" shortcut
            Button("Vai a oggi") {
                selectedDate = .now
                displayedMonth = .now
                onSelect()
            }
            .font(.subheadline).foregroundStyle(RitmoTheme.accent)
            .padding(.bottom, 4)
        }
        .padding()
        .onAppear { displayedMonth = selectedDate }
    }

    private func shiftMonth(_ delta: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }
}
