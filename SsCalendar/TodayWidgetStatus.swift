import Foundation

/// 잠금화면 Today/Next 위젯이 "지금" 보여줄 상태.
/// - `today`: Today 위젯이 보여줄 단 하나의 일정. 진행 중인 시간 지정 일정 → 가장 가까운 예정
///   시간 지정 일정 → 오늘의 종일 일정 순으로 고른다(자세한 우선순위는 Resolver 참고).
/// - `isTodayOngoing`: `today`가 진행 중인 시간 지정 일정으로 선택됐는지 여부("진행" 표시 여부).
/// - `next`: Next 위젯이 보여줄 일정. `today`로 선택되지 않은 것 중 가장 빠른 예정 일정.
struct TodayWidgetStatus: Hashable {
    let today: CalendarDisplayOccurrence?
    let isTodayOngoing: Bool
    let next: CalendarDisplayOccurrence?

    static let empty = TodayWidgetStatus(today: nil, isTodayOngoing: false, next: nil)
}

/// 오늘 하루의 occurrence 목록에서 Today/Next 위젯이 각각 보여줄 일정을 고르는 순수 판별 로직.
/// EventKit·SwiftData·WidgetKit에 의존하지 않아 유닛 테스트로 검증할 수 있다.
/// 잠금화면 Today·Next 위젯(TodayWidgetProvider/NextWidgetProvider)과 테스트가 함께 사용한다.
enum TodayWidgetStatusResolver {
    /// - Parameters:
    ///   - todayOccurrences: 오늘 하루와 겹치는 occurrence 전체(로컬+시스템, 순서 무관).
    ///   - now: 판별 기준 시각.
    ///   - calendar: 날짜 경계 계산에 쓰는 캘린더. 앱의 다른 "오늘" 계산과 같은 기준을 써야 한다.
    ///
    /// Today 선택 우선순위(확정 기획):
    /// 1. 진행 중인 시간 지정 일정
    /// 2. 가장 가까운 미래의 시간 지정 일정
    /// 3. 위 두 종류가 없으면 오늘에 해당하는 종일 일정
    /// 4. 모두 없으면 nil("오늘 일정 없음")
    ///
    /// 규칙:
    /// - 시간 지정 일정의 "진행 중"은 `startDate <= now < endDate`로 판단한다.
    /// - 종일 일정은 특정 시각이 없으므로 "오늘에 해당함"을 오늘 날짜 포함 여부(`occurs(on:)`)로 판단한다.
    /// - 진행 중인 시간 지정 일정이 여러 개면 종료가 가장 빠른 일정을 대표로 고른다.
    /// - "진행" 표시(`isTodayOngoing`)는 위 1번 경로로 선택됐을 때만 true다. 3번(종일) 경로는 이미
    ///   시간 대신 "종일"로 표시되므로 별도의 "진행" 배지를 붙이지 않는다.
    /// - Next는 Today가 고른 것을 제외한, 아직 시작하지 않은 시간 지정 일정 중 가장 먼저 시작하는 것이다.
    ///   종일 일정은 특정 시작 시각이 없어 Next로는 표시하지 않는다.
    /// - 정렬 기준이 같으면 occurrence id로 한 번 더 비교해, 입력 순서가 달라도 항상 같은 결과를 고른다.
    static func status(
        from todayOccurrences: [CalendarDisplayOccurrence],
        now: Date,
        calendar: Calendar
    ) -> TodayWidgetStatus {
        let today = calendar.startOfDay(for: now)

        let timed = todayOccurrences.filter { !$0.isAllDay }
        let ongoingAllDay = todayOccurrences.filter {
            $0.isAllDay && $0.occurs(on: today, calendar: calendar)
        }
        let ongoingTimed = timed.filter { $0.startDate <= now && now < $0.endDate }
        let upcomingTimed = timed.filter { $0.startDate > now }

        let ongoingTimedPick = ongoingTimed.min { ($0.endDate, $0.id) < ($1.endDate, $1.id) }
        let upcomingTimedPick = upcomingTimed.min { ($0.startDate, $0.id) < ($1.startDate, $1.id) }
        let ongoingAllDayPick = ongoingAllDay.min { ($0.startDate, $0.id) < ($1.startDate, $1.id) }

        // 1) 진행 중인 시간 지정 일정 → 2) 가장 가까운 미래 시간 지정 일정 → 3) 오늘의 종일 일정 순.
        let todayPick = ongoingTimedPick ?? upcomingTimedPick ?? ongoingAllDayPick

        // todayPick과 동일한 occurrence가 Next로 중복 선택되지 않도록 id로 명시적으로 제외한다.
        let next = upcomingTimed
            .filter { $0.id != todayPick?.id }
            .min { ($0.startDate, $0.id) < ($1.startDate, $1.id) }

        return TodayWidgetStatus(
            today: todayPick,
            isTodayOngoing: todayPick != nil && todayPick?.id == ongoingTimedPick?.id,
            next: next
        )
    }
}
