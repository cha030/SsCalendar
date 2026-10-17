import SwiftUI

/// 1년 12개월을 한 화면에 모두 보여주는 연간 달력(Step 5-1). 월간 달력(CalendarView)과는 별개의
/// 전체 화면 모달로 띄운다 — 연도 좌우 스와이프가 월간 화면의 날짜 스와이프·엣지 뒤로가기 제스처와
/// 섞이지 않게 하기 위해서다(fullScreenCover는 sheet와 달리 기본 인터랙티브 닫기 제스처가 없다).
///
/// 터치 대상은 날짜가 아니라 월이다. 일정 제목·막대, 공휴일 명칭, 음력은 의도적으로 표시하지 않는다.
struct YearCalendarView: View {
    let calendar: Calendar
    let onSelectMonth: (Int, Int) -> Void
    let onClose: () -> Void

    @State private var displayedYear: Int
    @State private var yearChangeDirection: YearChangeDirection = .toNextYear
    @State private var isEditingYear = false
    @State private var yearInputText = ""
    /// 편집을 시작한 시점의(= 아직 사용자가 아무것도 입력하지 않은) 원본 텍스트. 입력 화면을 여는
    /// 순간 기존 연도 숫자를 그대로 채워 넣는데, 이 값이 우연히 4자리라고 해서(예: "2026") 그
    /// 자체로 다시 확정(이동)해 버리면 안 된다 — 아래 onChange의 가드에서 이 값과 비교해 막는다.
    @State private var yearInputTextAtEditStart = ""
    /// 입력 화면을 열 때 기존 숫자가 전체 선택된 상태로 보이게 하는 데 쓴다(iOS 네이티브 숫자
    /// 필드처럼, 지우지 않고 바로 새 숫자를 입력하면 선택 영역이 통째로 교체된다).
    @State private var yearInputSelection: TextSelection?
    @FocusState private var isYearFieldFocused: Bool

    /// Calendar(DateComponents 기반 연산)가 안전하게 처리할 수 있다고 보는 연도 범위.
    /// 그레고리력 자체는 1582년부터지만, 이 앱은 과거 연도 열람도 자유롭게 허용하기 위해
    /// 1~9999(4자리)로 넉넉히 잡는다. 좌우 스와이프는 이 범위를 그대로 쓴다.
    private let yearRange = 1...9999
    /// 직접 입력으로는 4자리 연도만 지원한다(요청 사항). 스와이프 탐색 범위(yearRange)와는
    /// 별개로, 타이핑 중 자동 확정 판정에만 쓰는 좁은 범위다.
    private let directInputYearRange = 1000...9999

    init(
        initialYear: Int,
        calendar: Calendar,
        onSelectMonth: @escaping (Int, Int) -> Void,
        onClose: @escaping () -> Void
    ) {
        _displayedYear = State(initialValue: initialYear)
        self.calendar = calendar
        self.onSelectMonth = onSelectMonth
        self.onClose = onClose
    }

    private enum YearChangeDirection {
        case toNextYear
        case toPreviousYear
    }

    private var todayComponents: DateComponents {
        calendar.dateComponents([.year, .month], from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            GeometryReader { geometry in
                monthGrid(in: geometry.size)
                    .id(displayedYear)
                    .transition(gridTransition)
            }
        }
        // 연도 입력 중 "바깥 영역"(월 카드·닫기 버튼 등 자체 제스처가 있는 요소가 아닌 곳)을
        // 탭하면 입력을 포기하고 원래 연도로 돌아간다. 월 카드마다 이미 onTapGesture가 있어서,
        // 그 위를 탭하면 이 바깥 제스처보다 먼저 처리된다(더 안쪽 뷰의 제스처가 우선한다).
        .contentShape(Rectangle())
        .onTapGesture {
            isYearFieldFocused = false
        }
        .simultaneousGesture(yearSwipeGesture)
        .onChange(of: isYearFieldFocused) { _, isFocused in
            // handleYearInputChange의 자동 확정을 거치지 않고 포커스를 잃은 경우 — 입력을 취소하고
            // 화면에 보이던 연도는 그대로 둔다(편집 중에는 displayedYear를 바꾸지 않았으므로
            // 따로 되돌릴 값도 없다).
            if !isFocused && isEditingYear {
                isEditingYear = false
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
            }
            .accessibilityLabel(Text("닫기", comment: "연간 달력 닫기 버튼"))

            Spacer()

            // 이전·다음 연도 화살표는 없앴다(좌우 스와이프로 대체). 연도는 중앙에 숫자만 표시한다.
            yearTitle

            Spacer()

            // 왼쪽 닫기 버튼과 균형을 맞춰 가운데 연도 타이틀이 실제로 중앙에 오도록 하는
            // 투명 자리 표시자(탭 불가).
            Image(systemName: "xmark")
                .font(.body)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var yearTitle: some View {
        if isEditingYear {
            // text:selection: 이니셜라이저로 포커스가 들어오는 시점에 기존 숫자가 전체 선택된
            // 상태를 그대로 표현한다(beginEditingYear에서 선택 범위를 전체로 미리 채워 둔다).
            // 전체 선택된 상태에서 숫자를 입력하면 iOS 표준 동작대로 선택 영역이 통째로 교체되므로,
            // 기존 숫자를 하나씩 지울 필요가 없다.
            TextField("", text: $yearInputText, selection: $yearInputSelection)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title)
                .fontWeight(.semibold)
                .frame(minWidth: 90)
                .focused($isYearFieldFocused)
                .onAppear { isYearFieldFocused = true }
                .onChange(of: yearInputText) { _, newValue in
                    handleYearInputChange(newValue)
                }
        } else {
            Text(yearTitleDate.formatted(.dateTime.year().locale(calendar.locale ?? .current)))
                .font(.title)
                .fontWeight(.semibold)
                .frame(minWidth: 90)
                // 스와이프로 연도가 바뀌면 자릿수가 달라질 수 있다(예: "999" → "1000"). changeYear(by:)가
                // displayedYear 변경을 withAnimation으로 감싸므로, 이 타이틀도 같이 리레이아웃되며
                // 잠깐 좌우로 흔들려 보일 수 있어(DayScheduleView의 날짜 제목과 같은 문제) 명시적으로
                // 애니메이션을 끈다. 월 그리드 전환 애니메이션에는 영향이 없다.
                .animation(nil, value: displayedYear)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginEditingYear()
                }
        }
    }

    private var yearTitleDate: Date {
        calendar.date(from: DateComponents(year: displayedYear, month: 1, day: 1)) ?? Date()
    }

    private func beginEditingYear() {
        let text = String(displayedYear)
        yearInputText = text
        yearInputTextAtEditStart = text
        yearInputSelection = TextSelection(range: text.startIndex..<text.endIndex)
        isEditingYear = true
    }

    /// 입력 중인 글자를 검사해, 숫자가 아닌 문자를 걸러내고(붙여넣기 포함) 4자리로 제한한 뒤,
    /// "기존 값과 다른, 유효한 4자리 연도"가 완성된 순간에만 한 번 자동으로 이동한다.
    private func handleYearInputChange(_ newValue: String) {
        let digitsOnly = String(newValue.filter(\.isNumber).prefix(4))

        guard digitsOnly == newValue else {
            // 필터링된 값으로 바꿔 쓰면 이 onChange가 다시 호출되어, 아래 커밋 판정은
            // 그 다음 호출(이미 숫자 4자리 이하인 값)에서 수행된다. yearInputSelection이 가리키던
            // String.Index는 필터링 전(더 긴) 문자열 기준이라, text만 바꾸고 selection을 그대로
            // 두면 더 짧아진 새 문자열에서 범위를 벗어난 인덱스를 참조하게 될 수 있다 — 안전하게
            // 새 문자열 끝의 삽입 지점으로 같이 재설정한다.
            yearInputText = digitsOnly
            yearInputSelection = TextSelection(insertionPoint: digitsOnly.endIndex)
            return
        }

        // 입력 화면을 여는 순간 채워 넣은 원래 숫자("2026")가 그대로인 상태(사용자가 아직
        // 아무것도 타이핑하지 않음)라면, 그 자체로 다시 확정(이동)하지 않는다.
        guard digitsOnly != yearInputTextAtEditStart else { return }

        guard
            digitsOnly.count == 4,
            let year = Int(digitsOnly),
            directInputYearRange.contains(year)
        else {
            return
        }

        displayedYear = year
        isEditingYear = false
        isYearFieldFocused = false
    }

    private func changeYear(by delta: Int) {
        let candidate = displayedYear + delta
        guard yearRange.contains(candidate) else { return }
        yearChangeDirection = delta > 0 ? .toNextYear : .toPreviousYear
        withAnimation(.easeInOut(duration: 0.22)) {
            displayedYear = candidate
        }
    }

    private var yearSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // DayScheduleView의 날짜 스와이프와 같은 기준(세로 스크롤·탭과의 오인식 방지)을 쓴다.
                guard abs(horizontal) > 60, abs(horizontal) > abs(vertical) * 2 else { return }
                changeYear(by: horizontal < 0 ? 1 : -1)
            }
    }

    private var gridTransition: AnyTransition {
        let insertionEdge: Edge = yearChangeDirection == .toNextYear ? .trailing : .leading
        let removalEdge: Edge = yearChangeDirection == .toNextYear ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private let columnCount = 3
    private let rowCount = 4

    private func monthGrid(in size: CGSize) -> some View {
        let horizontalPadding: CGFloat = 8
        let interItemSpacing: CGFloat = 6
        let availableWidth = size.width
            - horizontalPadding * 2
            - interItemSpacing * CGFloat(columnCount - 1)
        let availableHeight = size.height
            - interItemSpacing * CGFloat(rowCount - 1)
        let cardWidth = max(0, availableWidth / CGFloat(columnCount))
        let cardHeight = max(0, availableHeight / CGFloat(rowCount))

        return VStack(spacing: interItemSpacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: interItemSpacing) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        let month = row * columnCount + column + 1
                        MiniMonthView(
                            year: displayedYear,
                            month: month,
                            calendar: calendar,
                            isCurrentMonth: todayComponents.year == displayedYear
                                && todayComponents.month == month,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectMonth(displayedYear, month)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 4)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// 연간 달력의 미니 월 카드 한 칸. 날짜 숫자만 표시하고(일정·공휴일·음력 제외), 월 카드 전체가
/// 탭 대상이므로(날짜 숫자 자체는 탭 불가) 날짜 셀에는 제스처를 달지 않는다.
private struct MiniMonthView: View {
    let year: Int
    let month: Int
    let calendar: Calendar
    let isCurrentMonth: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    @AppStorage(HolidayCountry.storageKey, store: HolidayCountry.settingsStore)
    private var holidayCountryRawValue = HolidayCountry.southKorea.rawValue

    private var usesColoredWeekends: Bool {
        (HolidayCountry(rawValue: holidayCountryRawValue) ?? .southKorea).usesColoredWeekendsForDisplay
    }

    private static let titleHeight: CGFloat = 18

    private var monthStartDate: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private var grid: YearMiniMonthGrid {
        YearMiniMonthGrid(year: year, month: month, calendar: calendar)
    }

    private var cellWidth: CGFloat {
        cardWidth / CGFloat(YearMiniMonthGrid.columnCount)
    }

    private var cellHeight: CGFloat {
        max(0, cardHeight - Self.titleHeight) / CGFloat(YearMiniMonthGrid.rowCount)
    }

    /// 날짜 숫자 폰트 크기를 실제 날짜 칸 너비(cellWidth) 기준으로 계산한다. 특정 기기 이름으로
    /// 분기하지 않고, 칸이 넓어지면(iPhone Pro/Pro Max 등) 자연스럽게 커지고 좁아지면(iPhone 13
    /// mini 등) 자연스럽게 작아진다. 두 자리 숫자("31")가 칸 안에 들어가는 비율(칸 폭의 60%)을
    /// 기준으로 잡고, 8~13pt로 제한해 너무 작아 안 보이거나 너무 커서 옆 칸을 침범하지 않게 한다.
    /// cellHeight가 극단적으로 작아지는 경우를 대비해 세로 기준 상한도 같이 둔다.
    private var dayFontSize: CGFloat {
        let widthBased = cellWidth * 0.6
        let clamped = min(max(widthBased, 8), 13)
        return min(clamped, cellHeight * 0.5)
    }

    /// 월 이름 폰트 크기도 같은 원칙으로 카드 너비(cardWidth) 기준으로 계산한다.
    private var monthTitleFontSize: CGFloat {
        min(max(cardWidth * 0.1, 9), 13)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(monthStartDate.formatted(.dateTime.month(.abbreviated).locale(calendar.locale ?? .current)))
                .font(.system(size: monthTitleFontSize))
                .fontWeight(isCurrentMonth ? .bold : .medium)
                .foregroundStyle(isCurrentMonth ? Color.accentColor : Color.primary)
                .frame(height: Self.titleHeight)

            VStack(spacing: 0) {
                ForEach(0..<YearMiniMonthGrid.rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<YearMiniMonthGrid.columnCount, id: \.self) { column in
                            let index = row * YearMiniMonthGrid.columnCount + column
                            dayCell(for: grid.days[index], weekdayColumn: column)
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private func dayCell(for date: Date?, weekdayColumn: Int) -> some View {
        if let date {
            let isToday = calendar.isDateInToday(date)
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.accentColor)
                        .padding(1.5)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: dayFontSize))
                    .foregroundStyle(isToday ? Color.white : dayColor(weekdayColumn: weekdayColumn))
            }
        } else {
            Color.clear
        }
    }

    /// 기존 월간 달력(CalendarDayCell.dateColor)과 같은 원칙: 일요일(0번 칸) 빨강, 토요일(6번 칸) 파랑.
    /// calendar.firstWeekday가 1(일요일)로 고정돼 있어 그리드 칸 위치가 곧 요일을 뜻한다.
    private func dayColor(weekdayColumn: Int) -> Color {
        if usesColoredWeekends, weekdayColumn == 0 {
            return .red
        } else if usesColoredWeekends, weekdayColumn == YearMiniMonthGrid.columnCount - 1 {
            return .blue
        } else {
            return .primary
        }
    }
}

/// 연간 달력의 미니 월 그리드가 쓰는 순수 날짜 계산. 항상 6행×7열(42칸) 고정 그리드를 만들어, 실제
/// 주 수(4~6주)가 다른 달이 섞여 있어도 3×4 레이아웃의 모든 월 카드 높이가 똑같이 유지되게 한다.
/// WeekEventLayout과 같은 이유로, 유닛 테스트 타깃에서도 생성할 수 있도록 internal로 둔다.
struct YearMiniMonthGrid {
    static let rowCount = 6
    static let columnCount = 7

    /// 42칸(6행×7열). 그 달에 속하지 않는 앞뒤 공백 칸은 nil.
    let days: [Date?]

    init(year: Int, month: Int, calendar: Calendar) {
        let totalCells = Self.rowCount * Self.columnCount

        guard
            let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else {
            days = Array(repeating: nil, count: totalCells)
            return
        }

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        // calendar.firstWeekday 기준으로 1일이 그리드의 몇 번째 칸(0=첫 칸)에 와야 하는지 계산한다.
        let leadingBlankCount = (weekday - calendar.firstWeekday + 7) % 7

        var result: [Date?] = Array(repeating: nil, count: leadingBlankCount)
        for offset in 0..<dayRange.count {
            if let date = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                result.append(date)
            }
        }
        while result.count < totalCells {
            result.append(nil)
        }

        days = Array(result.prefix(totalCells))
    }
}

#Preview {
    YearCalendarView(
        initialYear: 2026,
        calendar: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale.current
            calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
            calendar.firstWeekday = 1
            return calendar
        }(),
        onSelectMonth: { _, _ in },
        onClose: {}
    )
}
