import SwiftUI

struct CalendarView: View {
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var schedulePath: [Date] = []

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 1
        return calendar
    }

    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 0),
        count: 7
    )

    var body: some View {
        NavigationStack(path: $schedulePath) {
            VStack(spacing: 0) {

            // 상단 월 이동
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }

                Text("\(calendar.component(.month, from: currentDate))월")
                    .font(.title)
                    .fontWeight(.semibold)
                    .frame(minWidth: 70)

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }

                Spacer()

                Button("오늘") {
                    let today = Date()
                    currentDate = today
                    selectedDate = today
                }
                .font(.body)
            }
            .padding(.horizontal)
            .padding(.top)

            // 요일
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                    Text(weekday)
                        .font(.subheadline)
                        .foregroundStyle(
                            index == 0 ? .red :
                            index == 6 ? .blue :
                            .primary
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)

            Divider()

            // 달력
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(visibleDates, id: \.self) { date in

                    let isCurrentMonth = calendar.isDate(
                        date,
                        equalTo: currentDate,
                        toGranularity: .month
                    )

                    CalendarDayCell(
                        date: date,
                        isCurrentMonth: isCurrentMonth,
                        isToday: calendar.isDateInToday(date),
                        isSelected: calendar.isDate(
                            date,
                            inSameDayAs: selectedDate
                        ),
                        calendar: calendar
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if calendar.isDate(date, inSameDayAs: selectedDate) {
                            openSchedule(for: date)
                        } else {
                            selectedDate = date
                        }
                    }
                }
            }

                Spacer()
            }
            .navigationDestination(for: Date.self) { date in
                DayScheduleView(date: date)
            }
        }
    }

    private func openSchedule(for date: Date) {
        schedulePath.append(date)
    }

    // 이전 / 다음 달
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(
            byAdding: .month,
            value: value,
            to: currentDate
        ) {
            currentDate = newDate
        }
    }

    // 화면에 필요한 주만 날짜 생성
    private var visibleDates: [Date] {
        guard
            let monthInterval = calendar.dateInterval(
                of: .month,
                for: currentDate
            )
        else {
            return []
        }

        let firstDay = monthInterval.start

        guard
            let firstWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: firstDay
            )
        else {
            return []
        }

        guard
            let lastDay = calendar.date(
                byAdding: .day,
                value: -1,
                to: monthInterval.end
            )
        else {
            return []
        }

        guard
            let lastWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: lastDay
            )
        else {
            return []
        }

        var dates: [Date] = []
        var date = firstWeek.start

        while date < lastWeek.end {
            dates.append(date)

            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }

            date = nextDate
        }

        return dates
    }
}

#Preview {
    CalendarView()
}
