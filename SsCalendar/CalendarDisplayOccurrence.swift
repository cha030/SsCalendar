import Foundation
import SwiftUI
import UIKit

/// 화면 표시 전용 일정 값 타입. 저장하지 않으며 SwiftData `Event`에 종속되지 않는다.
/// 로컬(SwiftData) 일정과 시스템 캘린더(EventKit) 일정을 같은 형태로 합쳐 그리기 위해 사용한다.
struct CalendarDisplayOccurrence: Identifiable, Hashable {
    enum Source: Hashable {
        /// SsCalendar(SwiftData) 일정. 편집 시 이 ID로 원본 `Event`를 찾는다.
        case local(eventID: UUID)
        /// iOS 시스템 캘린더 일정. 원본은 EventKit에만 있으며 `reference`로 발생분을 다시 조회한다.
        case system(calendarTitle: String, reference: SystemCalendarEventReference)
    }

    /// 출처 접두어(`local:` / `system:`)를 붙여 서로 충돌하지 않는 ID.
    let id: String
    let source: Source
    let title: String
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let color: Color
    let importantMarker: ImportantMarker
    let createdAt: Date
    /// 반복 규칙이 원래 계산한 발생 시작 시각(개별 수정 override 이전). 개별 수정되지 않았거나
    /// 시스템 일정이면 startDate와 같다. 자체 반복 일정의 특정 발생분을 식별(개별 수정·삭제
    /// 예외 매칭)하는 데 쓰인다(Step 5-2).
    var originalStartDate: Date { _originalStartDate ?? startDate }
    private let _originalStartDate: Date?

    init(
        id: String,
        source: Source,
        title: String,
        isAllDay: Bool,
        startDate: Date,
        endDate: Date,
        color: Color,
        originalStartDate: Date? = nil,
        importantMarker: ImportantMarker = .none,
        createdAt: Date = .distantPast
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.endDate = endDate
        self.color = color
        self.importantMarker = importantMarker
        self.createdAt = createdAt
        self._originalStartDate = originalStartDate
    }

    var isSystem: Bool {
        if case .system = source { return true }
        return false
    }

    var localEventID: UUID? {
        if case .local(let eventID) = source { return eventID }
        return nil
    }

    var systemEventReference: SystemCalendarEventReference? {
        if case .system(_, let reference) = source { return reference }
        return nil
    }

    var sortStartDate: Date {
        guard isAllDay else { return startDate }
        switch source {
        case .local:
            return AllDayDate.storageDate(for: startDate)
        case .system:
            return startDate
        }
    }

    // 아래 두 날짜 계산은 EventOccurrence와 동일한 규칙을 따른다(기존 로컬 일정 배치 보존).

    func occurs(on date: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return false
        }

        if isAllDay {
            let eventStartDay = calendar.startOfDay(
                for: AllDayDate.displayDate(
                    fromStorageDate: AllDayDate.storageDate(for: startDate, calendar: calendar),
                    calendar: calendar
                )
            )
            let eventEndDay = calendar.startOfDay(
                for: AllDayDate.displayDate(
                    fromStorageDate: AllDayDate.storageDate(for: endDate, calendar: calendar),
                    calendar: calendar
                )
            )
            return eventStartDay <= dayStart && dayStart <= eventEndDay
        }

        if startDate == endDate {
            return startDate >= dayStart && startDate < nextDayStart
        }

        return startDate < nextDayStart && endDate > dayStart
    }

    func occupiedDayRange(calendar: Calendar) -> ClosedRange<Date> {
        let firstDay: Date
        let endDay: Date
        if isAllDay {
            firstDay = calendar.startOfDay(
                for: AllDayDate.displayDate(
                    fromStorageDate: AllDayDate.storageDate(for: startDate, calendar: calendar),
                    calendar: calendar
                )
            )
            endDay = calendar.startOfDay(
                for: AllDayDate.displayDate(
                    fromStorageDate: AllDayDate.storageDate(for: endDate, calendar: calendar),
                    calendar: calendar
                )
            )
        } else {
            firstDay = calendar.startOfDay(for: startDate)
            endDay = calendar.startOfDay(for: endDate)
        }

        if isAllDay || startDate == endDate || endDate > endDay {
            return firstDay...max(firstDay, endDay)
        }

        let previousDay = calendar.date(
            byAdding: .day,
            value: -1,
            to: endDay
        ) ?? firstDay
        return firstDay...max(firstDay, previousDay)
    }
}

/// 시스템 캘린더 일정 발생분의 원본 식별 정보. EKEvent 객체 대신 값만 보관한다(SwiftData에 저장하지 않음).
/// `EKEventStore.event(withIdentifier:)`는 반복 일정의 첫 발생분만 돌려주고, 일정의 캘린더가 바뀌면
/// `eventIdentifier`도 바뀔 수 있으므로 여러 식별자와 발생 시각을 함께 보관해 특정 발생분을 다시 찾는다.
struct SystemCalendarEventReference: Hashable {
    let eventIdentifier: String?
    let calendarItemIdentifier: String
    /// 서버(iCloud·Google 등)가 부여한 식별자. 캘린더 이동 후 eventIdentifier가 바뀐 경우의 보조 키다.
    let externalIdentifier: String?
    let calendarIdentifier: String?
    /// 조회 시점의 발생분 시작 시각.
    let startDate: Date
    /// 반복 일정의 원래 발생 시각. 개별 발생분을 다른 시각으로 옮겨도(detached) 변하지 않는다.
    let occurrenceDate: Date?
    let isRecurring: Bool
}

// 앱/위젯 공유 파일(위젯 폴더에 심볼릭 링크). 앱 전용 타입(EventColor 등)에 의존하지 않는다.
// 로컬 일정 변환 init(local:)은 앱 전용 CalendarDisplayOccurrence+Local.swift에 있다.
extension CalendarDisplayOccurrence {
    /// 로컬/시스템 일정을 기존 EventOccurrenceService와 같은 기준(종일 우선, 시작 시각 순)으로 합친다.
    static func merged(
        local: [CalendarDisplayOccurrence],
        system: [CalendarDisplayOccurrence]
    ) -> [CalendarDisplayOccurrence] {
        guard !system.isEmpty else { return local }

        return (local + system).sorted { first, second in
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }

            return first.sortStartDate < second.sortStartDate
        }
    }
}

struct ImportantMarkerCandidate: Hashable, Sendable {
    let id: String
    let marker: ImportantMarker
    let firstDay: Date
    let createdAt: Date
}

enum ImportantMarkerSelection {
    static func marker(
        for date: Date,
        candidates: [ImportantMarkerCandidate],
        calendar: Calendar
    ) -> ImportantMarker {
        candidates
            .filter {
                $0.marker != .none && calendar.isDate($0.firstDay, inSameDayAs: date)
            }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id < $1.id
            }
            .first?.marker ?? .none
    }
}

enum ImportantMarkerStampMetrics {
    static let ringRadiusRatio: CGFloat = 1.15
    static let ringLineWidthRatio: CGFloat = 0.12
    static let rayCount = 8
    static let rayStartGapRatio: CGFloat = 0.22
    static let rayLengthRatio: CGFloat = 0.33

    struct Geometry: Equatable {
        let diameter: CGFloat
        let lineWidth: CGFloat
        let ringRadius: CGFloat
        let rayStart: CGFloat
        let rayEnd: CGFloat
    }

    static func geometry(
        forFontSize fontSize: CGFloat,
        maxDiameter: CGFloat? = nil,
        maxLineWidth: CGFloat? = nil
    ) -> Geometry {
        let requestedDiameter = 2 * (ringRadiusRatio + rayStartGapRatio + rayLengthRatio) * fontSize
        let diameter = min(requestedDiameter, maxDiameter ?? requestedDiameter)
        let scale = diameter / requestedDiameter
        return Geometry(
            diameter: diameter,
            lineWidth: min(
                ringLineWidthRatio * fontSize * scale,
                maxLineWidth ?? .greatestFiniteMagnitude
            ),
            ringRadius: ringRadiusRatio * fontSize * scale,
            rayStart: (ringRadiusRatio + rayStartGapRatio) * fontSize * scale,
            rayEnd: (ringRadiusRatio + rayStartGapRatio + rayLengthRatio) * fontSize * scale
        )
    }

    static func ringRadius(forFontSize fontSize: CGFloat) -> CGFloat {
        ringRadiusRatio * fontSize
    }
}

enum ImportantMarkerStyle {
    static var gold: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 235 / 255, green: 180 / 255, blue: 50 / 255, alpha: 1)
            }
            return UIColor(red: 214 / 255, green: 158 / 255, blue: 20 / 255, alpha: 1)
        })
    }
}

struct ImportantMarkerStamp: View {
    let marker: ImportantMarker
    var fontSize: CGFloat? = nil
    var maxDiameter: CGFloat? = nil
    var maxLineWidth: CGFloat? = nil

    @ScaledMetric(relativeTo: .body) private var scaledFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var scaledMaxDiameter: CGFloat = 40

    private var geometry: ImportantMarkerStampMetrics.Geometry {
        ImportantMarkerStampMetrics.geometry(
            forFontSize: fontSize ?? scaledFontSize,
            maxDiameter: maxDiameter ?? scaledMaxDiameter,
            maxLineWidth: maxLineWidth
        )
    }

    var body: some View {
        Group {
            switch marker {
            case .none:
                EmptyView()
            case .star:
                ImportantMarkerStarShape()
                    .stroke(ImportantMarkerStyle.gold, lineWidth: geometry.lineWidth)
            case .sun:
                ImportantMarkerSunShape(geometry: geometry)
                    .stroke(
                        ImportantMarkerStyle.gold,
                        style: StrokeStyle(
                            lineWidth: geometry.lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
        .frame(width: geometry.diameter, height: geometry.diameter)
        .rotationEffect(.degrees(10))
        .allowsHitTesting(false)
    }
}

private struct ImportantMarkerStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        var path = Path()

        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = (-Double.pi / 2) + (Double(index) * Double.pi / 5)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct ImportantMarkerSunShape: Shape {
    let geometry: ImportantMarkerStampMetrics.Geometry

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let scale = min(rect.width, rect.height) / geometry.diameter
        let ringRadius = geometry.ringRadius * scale
        let rayStart = geometry.rayStart * scale
        let rayEnd = geometry.rayEnd * scale
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))

        for index in 0..<ImportantMarkerStampMetrics.rayCount {
            let angle = -Double.pi / 2 + (Double(index) * 2 * Double.pi / Double(ImportantMarkerStampMetrics.rayCount))
            path.move(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * rayStart,
                y: center.y + CGFloat(sin(angle)) * rayStart
            ))
            path.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * rayEnd,
                y: center.y + CGFloat(sin(angle)) * rayEnd
            ))
        }
        return path
    }
}
