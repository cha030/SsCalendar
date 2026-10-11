import EventKit
import Foundation
import SwiftData
import SwiftUI

/// 위젯(잠금화면·홈 화면)의 D-Day 조회를 한 곳에 모은다(Step 5-2). 로컬(SwiftData)과 외부
/// (EventKit) 일정을 같은 기준으로 합친다 — 기존 LockScreenWidgetMoments/CalendarWidgetProvider가
/// 로컬·시스템 일정을 합치는 것과 같은 방식이다. 앱과 위젯이 함께 쓰므로 위젯 폴더에
/// 심볼릭 링크로 공유한다.
@MainActor
enum DDayWidgetSource {
    struct Item: Identifiable {
        let occurrence: CalendarDisplayOccurrence
        let daysRemaining: Int

        var id: String { occurrence.id }
    }

    /// 오늘(당일 포함) 이후이고 D-Day가 켜진 일정을, 가장 가까운 날짜 순으로 최대 `limit`개 반환한다.
    /// 반복 일정은 다음 발생일을 기준으로 한다(Step 5-2 반복 일정 D-Day 정책). 지난 일정(과거
    /// 날짜)은 D-Day 설정값과 무관하게 여기서 제외한다(설정 자체는 건드리지 않는다).
    static func items(now: Date = Date(), limit: Int) -> [Item] {
        let calendar = Calendar.current

        do {
            // WidgetDataStore는 위젯 타깃 전용 얇은 래퍼(내부적으로 SharedModelContainer를 그대로
            // 호출)라 앱 타깃에는 없다. 이 파일은 앱·위젯 양쪽에 공유되므로 둘 다에 있는
            // SharedModelContainer를 직접 쓴다.
            let container = try SharedModelContainer.makeSharedContainer()
            let context = ModelContext(container)

            let localOccurrences = try localDDayOccurrences(context: context, now: now, calendar: calendar)
            let externalOccurrences = externalDDayOccurrences(context: context, now: now, calendar: calendar)

            return (localOccurrences + externalOccurrences)
                .map { occurrence in
                    Item(
                        occurrence: occurrence,
                        daysRemaining: DDayCalculator.daysRemaining(
                            until: occurrence.startDate,
                            now: now,
                            calendar: calendar
                        )
                    )
                }
                .filter { $0.daysRemaining >= 0 }
                .sorted { $0.occurrence.startDate < $1.occurrence.startDate }
                .prefix(limit)
                .map { $0 }
        } catch {
            return []
        }
    }

    /// D-Day가 켜진 로컬 일정. 반복 일정은 EventOccurrenceService로 "오늘 이후 다음 발생일"을
    /// 찾아 그 날짜를 쓴다(기존 반복 전개 엔진을 그대로 재사용 — 새 계산식을 따로 만들지 않는다).
    /// 반복 종료 날짜(Event.repeatEndDate)와 개별 수정·삭제 예외(EventOccurrenceException,
    /// Step 5-2)를 모두 반영한다 — 종료된 반복이나 개별 삭제된 다음 발생분은 건너뛰고, 개별
    /// 수정된 발생분은 그 override된 제목·시간을 그대로 보여준다.
    private static func localDDayOccurrences(
        context: ModelContext,
        now: Date,
        calendar: Calendar
    ) throws -> [CalendarDisplayOccurrence] {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.isDDayEnabled }
        )
        let events = try context.fetch(descriptor)
        let exceptions = (try? context.fetch(FetchDescriptor<EventOccurrenceException>())) ?? []
        let exceptionsByEventID = Dictionary(grouping: exceptions, by: \.eventID)

        // 반복 일정 D-Day는 날짜 단위로 "오늘 포함 이후"를 기준으로 삼는다(기존 nextOccurrenceDate와
        // 같은 기준) — now의 시각과 무관하게 오늘 날짜는 항상 포함돼야 한다.
        let todayStart = calendar.startOfDay(for: now)
        guard let rangeEnd = calendar.date(byAdding: .year, value: 100, to: todayStart) else {
            return []
        }

        return events.map { event -> CalendarDisplayOccurrence in
            let eventExceptions = exceptionsByEventID[event.id] ?? []

            if let nextOccurrence = EventOccurrenceService.occurrences(
                for: event,
                intersecting: DateInterval(start: todayStart, end: rangeEnd),
                calendar: calendar,
                limit: 1,
                exceptions: eventExceptions
            ).first {
                return CalendarDisplayOccurrence(
                    id: "local:\(event.id.uuidString):\(nextOccurrence.startDate.timeIntervalSince1970)",
                    source: .local(eventID: event.id),
                    title: nextOccurrence.title,
                    isAllDay: nextOccurrence.isAllDay,
                    startDate: nextOccurrence.startDate,
                    endDate: nextOccurrence.endDate,
                    color: colorForLocalEventColorName(nextOccurrence.colorName),
                    originalStartDate: nextOccurrence.originalStartDate
                )
            }

            // 유효한 다음 발생분을 찾지 못했다(비반복 일정이 이미 지났거나, 반복이 끝났거나,
            // 남은 발생분이 모두 개별 삭제된 경우) — 기존처럼 event.startDate로 돌아간다. 보통
            // 과거라 위의 daysRemaining >= 0 필터에서 자연히 제외된다.
            let duration = max(0, event.endDate.timeIntervalSince(event.startDate))
            return CalendarDisplayOccurrence(
                id: "local:\(event.id.uuidString):\(event.startDate.timeIntervalSince1970)",
                source: .local(eventID: event.id),
                title: event.title,
                isAllDay: event.isAllDay,
                startDate: event.startDate,
                endDate: event.startDate.addingTimeInterval(duration),
                color: colorForLocalEventColorName(event.color),
                originalStartDate: event.startDate
            )
        }
    }

    /// 한 번에 조회할 기간(년). EventKit의 predicateForEvents(withStart:end:calendars:)는 "성능을
    /// 위해 한 번에 최대 4년 범위만 조회하며, 그보다 길면 처음 4년으로 줄인다"고 공식 문서에
    /// 명시돼 있다(Apple Developer Documentation 확인). 그 한도를 넘는 단일 쿼리를 보내지 않는다.
    private static let externalSearchChunkYears = 4
    /// 구간을 나눠 조회할 최대 횟수. 무제한 반복 조회를 금지하기 위한 고정 상한이다.
    /// 4년 × 3구간 = 최대 12년 이내에 다음 발생일이 있는 반복 시리즈까지 지원한다(1·2·3·5년
    /// 간격은 모두 1~2구간 안에 찾는다). 그보다 긴 간격(예: 13년 이상)은 찾지 못해 위젯에서
    /// 자연히 제외된다 — 이 범위를 벗어나는 경우는 지원하지 않는다고 명확히 밝힌다.
    private static let externalSearchMaxChunks = 3

    /// D-Day가 켜진 외부 일정. 연동 OFF·권한 없음이면 빈 배열 — 권한이 철회돼도 위젯에
    /// 잘못 남아 보이지 않는다.
    ///
    /// 켜진 설정이 실제로 속한 캘린더만 좁혀서(전체 캘린더가 아니라) 조회하고, 4년씩 구간을
    /// 나눠 순차 조회하면서 매칭되는 시리즈를 찾으면 그 시점에 더 이상 찾지 않는다(효율성).
    /// EventKit이 반복 규칙(복수 요일·예외 발생일·종료 조건·개별 회차 변경 포함)을 매번 새로
    /// 해석해 반환하므로 RRULE을 직접 계산하지 않고, 캐시도 두지 않는다 — 발생일이 바뀌거나
    /// 특정 회차가 삭제돼도 다음 조회에 항상 최신 상태가 그대로 반영된다.
    private static func externalDDayOccurrences(
        context: ModelContext,
        now: Date,
        calendar: Calendar
    ) -> [CalendarDisplayOccurrence] {
        guard let defaults = SystemCalendarQuery.sharedDefaults() else { return [] }
        guard SystemCalendarQuery.isEnabled(in: defaults), SystemCalendarQuery.hasFullAccess else { return [] }

        let settings = (try? context.fetch(FetchDescriptor<ExternalEventDDaySetting>())) ?? []
        let enabledSettings = settings.filter(\.isEnabled)
        guard !enabledSettings.isEmpty else { return [] }

        let store = EKEventStore()
        let hiddenCalendarIDs = SystemCalendarQuery.hiddenCalendarIDs(in: defaults)

        // D-Day가 켜진 시리즈가 저장된 calendarIdentifier에 실제로 존재하는 캘린더만 조회
        // 대상으로 좁힌다. 계정 제거 등으로 더 이상 없는 캘린더는 자연히 걸러진다.
        let relevantCalendarIDs = Set(enabledSettings.compactMap(\.calendarIdentifier))
            .subtracting(hiddenCalendarIDs)
        let relevantCalendars = store.calendars(for: .event)
            .filter { relevantCalendarIDs.contains($0.calendarIdentifier) }
        guard !relevantCalendars.isEmpty else { return [] }

        var bestByCalendarItem: [String: CalendarDisplayOccurrence] = [:]
        var remainingSettings = enabledSettings
        var searchStart = calendar.startOfDay(for: now)

        for _ in 0..<externalSearchMaxChunks {
            guard !remainingSettings.isEmpty else { break }
            guard let searchEnd = calendar.date(
                byAdding: .year,
                value: externalSearchChunkYears,
                to: searchStart
            ) else { break }

            let predicate = store.predicateForEvents(
                withStart: searchStart,
                end: searchEnd,
                calendars: relevantCalendars
            )

            let chunkOccurrences = store.events(matching: predicate).map(SystemCalendarQuery.displayOccurrence(for:))
            for occurrence in bestMatchingOccurrences(from: chunkOccurrences, enabledSettings: remainingSettings) {
                guard let reference = occurrence.systemEventReference else { continue }
                let key = reference.calendarItemIdentifier
                if let existing = bestByCalendarItem[key], existing.startDate <= occurrence.startDate {
                    continue
                }
                bestByCalendarItem[key] = occurrence
            }

            // 이번 구간에서 발생분을 찾은 시리즈는 다음 구간부터 더 찾지 않는다. 과거(발생분
            // 단위) 정책 때 같은 시리즈에 설정이 여러 개 남아 있어도 전부 함께 제외된다.
            let foundReferences = bestByCalendarItem.values.compactMap(\.systemEventReference)
            remainingSettings.removeAll { setting in
                foundReferences.contains { setting.reference.matchesSeries(of: $0) }
            }

            searchStart = searchEnd
        }

        return Array(bestByCalendarItem.values)
    }

    /// 조회된 발생분 중 켜진 설정에 매칭되는 것만, 시리즈(calendarItemIdentifier)별로 가장 이른
    /// 것 하나씩 남긴다. EventKit 조회와 분리된 순수 로직이라 실제 캘린더 데이터 없이도 단위
    /// 테스트로 검증할 수 있다(반복 시리즈 중복 제거, 서로 다른 시리즈 오매칭 방지).
    static func bestMatchingOccurrences(
        from occurrences: [CalendarDisplayOccurrence],
        enabledSettings: [ExternalEventDDaySetting]
    ) -> [CalendarDisplayOccurrence] {
        var best: [String: CalendarDisplayOccurrence] = [:]
        for occurrence in occurrences {
            guard let reference = occurrence.systemEventReference else { continue }
            guard enabledSettings.contains(where: { $0.reference.matchesSeries(of: reference) }) else {
                continue
            }

            let key = reference.calendarItemIdentifier
            if let existing = best[key], existing.startDate <= occurrence.startDate {
                continue
            }
            best[key] = occurrence
        }
        return Array(best.values)
    }

    /// EventColor(앱 전용 타입)에 의존하지 않고 기존 4색 규칙을 그대로 옮긴 것이다
    /// (CalendarWidgetView.swift의 CalendarWidgetColor와 같은 값).
    private static func colorForLocalEventColorName(_ name: String) -> Color {
        switch name {
        case "빨간색": return .red
        case "초록색": return .green
        case "보라색": return .purple
        case "파란색": return .blue
        default: return .blue
        }
    }
}
