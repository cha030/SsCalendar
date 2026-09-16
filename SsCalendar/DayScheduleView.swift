import SwiftUI

struct DayScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEventEditor = false

    let date: Date

    private var dateTitle: String {
        date.formatted(
            Date.FormatStyle()
                .month(.defaultDigits)
                .day()
                .weekday(.wide)
                .locale(Locale(identifier: "ko_KR"))
        )
    }

    var body: some View {
        ZStack {
            List {
                // 향후 일정 목록을 이곳에 표시합니다.
            }

            Text("일정이 없습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("뒤로가기")
            }

            ToolbarItem(placement: .principal) {
                Text(dateTitle)
                    .font(.headline)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEventEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("일정 추가")
            }
        }
        .sheet(isPresented: $isPresentingEventEditor) {
            NavigationStack {
                EventEditorView(date: date)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DayScheduleView(date: Date())
    }
}
