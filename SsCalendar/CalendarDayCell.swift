import SwiftUI

struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let calendar: Calendar

    var body: some View {
        ZStack(alignment: .top) {

            if isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .padding(.top, 3)
            }

            if isSelected {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 38, height: 38)
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.body)
                .foregroundStyle(
                    isToday
                    ? Color.white
                    : dateColor
                )
                .padding(.top, 8)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 100,
            alignment: .top
        )
    }

    private var dateColor: Color {
        if !isCurrentMonth {
            return .secondary.opacity(0.45)
        }

        let weekday = calendar.component(.weekday, from: date)

        if weekday == 1 {
            return .red
        } else if weekday == 7 {
            return .blue
        } else {
            return .primary
        }
    }
}

#Preview {
    CalendarDayCell(
        date: Date(),
        isCurrentMonth: true,
        isToday: true,
        isSelected: true,
        calendar: Calendar.current
    )
}
