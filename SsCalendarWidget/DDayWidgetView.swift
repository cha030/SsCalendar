import SwiftUI
import WidgetKit

/// 잠금화면 `accessoryRectangular` 전용 D-Day 뷰. Today/Next 위젯(TodayWidgetView)과 같은
/// vibrant 렌더링 원칙(아이콘+텍스트 중심, 색상 없음)을 따른다.
///
/// Today/Next 위젯(TodayWidgetView/NextWidgetView)이 본문(LockScreenWidgetContent)은 공유하되
/// 최상위 위젯 View 타입(.widgetURL을 직접 거는 타입)은 kind마다 따로 둔 것과 같은 이유로,
/// 이 D-Day 위젯도 본문(DDayLockScreenContent)만 공유하고 최상위 타입은 DDayNextWidgetView로
/// 분리했다 — 실기기에서 D-Day Next를 탭하면 D-Day(첫 번째) 위젯으로 이동하는 문제가 있었는데,
/// 두 kind가 최상위 View 타입(DDayWidgetView)을 그대로 공유하고 있었던 것이 유일하게 확인된
/// 구조적 차이였다(Today/Next는 애초에 공유하지 않음).
struct DDayWidgetView: View {
    let entry: DDayWidgetEntry

    var body: some View {
        DDayLockScreenContent(
            item: entry.item,
            emptyText: String(localized: "D-Day 일정 없음")
        )
        .widgetURL(
            entry.item.map { CalendarWidgetDeepLink.dayURL(dateString: $0.dateString) }
                ?? CalendarWidgetDeepLink.monthURL(dateString: entry.dateString)
        )
    }
}

/// D-Day Next 전용 최상위 뷰(위 주석 참고). 내용은 DDayWidgetView와 같지만, kind별로 독립된
/// View 타입을 둬 잠금화면에서 두 위젯의 widgetURL이 서로 섞이지 않게 한다.
struct DDayNextWidgetView: View {
    let entry: DDayWidgetEntry

    var body: some View {
        DDayLockScreenContent(
            item: entry.item,
            emptyText: String(localized: "D-Day 일정 없음")
        )
        .widgetURL(
            entry.item.map { CalendarWidgetDeepLink.dayURL(dateString: $0.dateString) }
                ?? CalendarWidgetDeepLink.monthURL(dateString: entry.dateString)
        )
    }
}

/// D-Day·D-Day Next 위젯이 공유하는 본문.
struct DDayLockScreenContent: View {
    let item: DDayWidgetItemSummary?
    let emptyText: String

    var body: some View {
        Group {
            if let item {
                DDayLockScreenRow(item: item)
            } else {
                DDayLockScreenEmptyRow(text: emptyText)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

private struct DDayLockScreenEmptyRow: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.headline)
                .lineLimit(1)
        } icon: {
            ddayBrandIcon
        }
        .accessibilityElement(children: .combine)
    }
}

/// "[아이콘] D-N" + "제목" 두 줄로 보여준다. Today/Next와 같은 폰트 크기(.headline)를 쓴다.
private struct DDayLockScreenRow: View {
    let item: DDayWidgetItemSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ddayBrandIcon

                Text(DDayCalculator.displayText(forDaysRemaining: item.daysRemaining))
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

    @ViewBuilder
    private var titleText: some View {
        let text = Text(item.displayTitle)
        if item.isSensitiveTitle {
            text.privacySensitive()
        } else {
            text
        }
    }

    private var accessibilityText: String {
        "\(DDayCalculator.displayText(forDaysRemaining: item.daysRemaining)) \(item.displayTitle)"
    }
}

/// TodayWidgetView의 brandIcon과 같은 값(SR 심볼, 템플릿 렌더링).
private var ddayBrandIcon: some View {
    Image("SRBrandMark")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 11, height: 13)
        .foregroundStyle(.secondary)
}

#Preview("D-Day", as: .accessoryRectangular) {
    DDayWidget()
} timeline: {
    DDayWidgetEntry.placeholder
    DDayWidgetEntry.empty(for: .now)
}
