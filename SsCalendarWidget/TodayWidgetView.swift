import SwiftUI
import WidgetKit

/// 잠금화면 `accessoryRectangular` 전용 뷰. 시스템이 단색·반투명(vibrant)으로 렌더링하므로
/// 아이콘과 텍스트 중심으로 구성하고, 홈 위젯의 색상 중심 디자인은 가져오지 않는다.
///
/// 브랜드 아이콘은 기존 앱 아이콘(SsCalendarIcon.png) 중앙의 SR 심볼만 오려낸 템플릿 이미지
/// (Assets.xcassets의 SRBrandMark)를 쓴다. 원본 전체(불투명 배경·빨간 상단·입체 그림자 포함)는
/// vibrant 렌더링에서 흰 사각형 덩어리로만 보이므로 그대로 쓸 수 없어, SR 글자 획만 추출해
/// 투명 배경의 단색 실루엣으로 만들었다(SRBrandMark.imageset 생성 과정 참고).
struct TodayWidgetView: View {
    let entry: TodayWidgetEntry

    var body: some View {
        LockScreenWidgetContent(
            occurrence: entry.occurrence,
            emptyText: String(localized: "오늘 일정 없음")
        )
        .widgetURL(CalendarWidgetDeepLink.dayURL(for: entry.date))
    }
}

/// Today·Next 위젯이 공유하는 본문. 일정 하나(있으면) 또는 빈 상태 문구만 보여준다.
struct LockScreenWidgetContent: View {
    let occurrence: TodayWidgetOccurrenceSummary?
    let emptyText: String

    var body: some View {
        Group {
            if let occurrence {
                LockScreenEventRow(occurrence: occurrence)
            } else {
                LockScreenEmptyRow(text: emptyText)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

/// 일정이 없을 때 보여주는 안내 한 줄.
private struct LockScreenEmptyRow: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.headline)
                .lineLimit(1)
        } icon: {
            brandIcon
        }
        .accessibilityElement(children: .combine)
    }
}

/// 일정 하나를 "[아이콘] [진행 점] 시간" + "제목" 두 줄로 보여준다.
/// 모든 텍스트는 같은 크기(.headline)를 쓰고, 시간은 절대 잘리거나 줄어들지 않는다.
private struct LockScreenEventRow: View {
    let occurrence: TodayWidgetOccurrenceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                brandIcon

                // "진행" 글자 대신 작은 점으로 표시해 시간이 들어갈 가로 공간을 확보한다.
                // 의미는 접근성 라벨(accessibilityText)에서 "진행"이라는 말로 그대로 전달한다.
                if occurrence.isOngoing {
                    ongoingDot
                }

                // 시간은 공통 크기(.headline)를 유지하되, 공간이 부족해도 줄어들거나
                // 잘리지 않도록 고정 크기로 그린다("오전 11:30" 같은 문자열이 다 보여야 한다).
                Text(timeText)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            titleText
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "진행 중"을 뜻하는 작은 점. 글자("진행")보다 훨씬 좁아 시간 표시 공간을 밀어내지 않는다.
    private var ongoingDot: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true) // 의미는 accessibilityText의 "진행"이라는 말로 전달한다.
    }

    @ViewBuilder
    private var titleText: some View {
        let text = Text(occurrence.displayTitle)
        // 대체 문구("일정 있음")는 이미 비식별 상태이므로 추가로 가릴 필요가 없다.
        if occurrence.isSensitiveTitle {
            text.privacySensitive()
        } else {
            text
        }
    }

    private var timeText: String {
        guard !occurrence.isAllDay else {
            return String(localized: "종일")
        }

        return occurrence.startDate.formatted(
            Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .locale(Locale.current)
        )
    }

    private var accessibilityText: String {
        let prefix = occurrence.isOngoing ? "\(String(localized: "진행")) " : ""
        return "\(prefix)\(timeText) \(occurrence.displayTitle)"
    }
}

/// 잠금화면 vibrant 렌더링에서도 자연스러운 작은 브랜드 마크(SR). 특정 색상에 의존하지 않도록
/// `.renderingMode(.template)`으로 그려 시스템이 알아서 단색 처리하게 하고, 일정 시간·제목보다
/// 작게 고정 크기로 둬 텍스트 영역을 침범하지 않게 한다.
private var brandIcon: some View {
    Image("SRBrandMark")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 11, height: 13)
        .foregroundStyle(.secondary)
}

#Preview("Today", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayWidgetEntry.placeholder
    TodayWidgetEntry.empty(for: .now)
}
