import Foundation

/// D-Day(남은 일수) 계산. 자체 일정(SwiftData `Event`)과 외부 일정(EventKit)이 같은 규칙을
/// 쓰도록 공통화한다(Step 5-2). 앱과 위젯이 함께 쓰므로 위젯 폴더에 심볼릭 링크로 공유한다
/// (CalendarWidgetConstants/SystemCalendarQuery와 같은 패턴).
///
/// 규칙:
/// - 시간이 아니라 "날짜" 차이로 계산한다(같은 날이면 몇 시든 D-Day).
/// - 호출하는 쪽이 넘긴 Calendar(시간대 포함)를 그대로 쓴다 — 이 파일은 임의로 시간대를 고르지 않는다.
/// - 반복 일정은 "최초/조회된 시작일" 하나만 기준으로 계산한다. 다음 발생일 기준 계산(반복 일정의
///   매 회차마다 D-Day를 다시 잡는 것)은 정책이 확정되지 않아 구현하지 않았다 — 완료 보고 참고.
enum DDayCalculator {
    /// targetDate가 속한 날짜와 오늘(now) 날짜의 차이(일). 음수면 지난 날짜, 0이면 당일, 양수면 D-N.
    static func daysRemaining(until targetDate: Date, now: Date = Date(), calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// 지난 일정(오늘보다 이전 날짜)인지 여부. 위젯은 이 값이 true인 일정을 표시 대상에서 제외한다.
    /// D-Day 설정값 자체는 건드리지 않는다(강제로 OFF하지 않는다).
    static func isPast(targetDate: Date, now: Date = Date(), calendar: Calendar) -> Bool {
        daysRemaining(until: targetDate, now: now, calendar: calendar) < 0
    }

    /// "D-10", "D-1", "D-Day" 표시 문자열. 지난 날짜(음수)는 호출하는 쪽에서 미리 걸러내고
    /// 이 함수를 부르지 않는 것을 전제로 한다(위젯 등에서 "지난 일정 제외" 규칙을 먼저 적용한다).
    static func displayText(forDaysRemaining days: Int) -> String {
        days <= 0 ? String(localized: "D-Day") : "D-\(days)"
    }
}
