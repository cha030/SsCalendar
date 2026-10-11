import SwiftUI
import WidgetKit

/// 홈 화면 D-Day 위젯(Small/Medium). 기존 월간 홈 위젯(CalendarWidgetView)과 달리 색상 중심이
/// 아니라, D-Day 숫자 가독성을 우선하는 단순한 목록으로 구성한다(불필요한 장식·애니메이션 없음).
///
/// 레이아웃 보완(실기기 확인): 이전에는 내용을 위쪽에 고정(topLeading)해 쌓다 보니 일정이
/// 적을 때(Small 1건, Medium 2건뿐) 아래쪽에 쓰이지 않는 여백이 많이 남았다. 지금은 family별로
/// 전용 레이아웃을 두고, 각 줄에 `maxHeight: .infinity`를 줘 위젯의 실제 세로 공간을 끝까지
/// 나눠 쓰도록 바꿨다 — 일정 개수와 무관하게 항상 위젯 전체 높이를 균형 있게 채운다.
struct DDayHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DDayHomeWidgetEntry

    /// Small은 1건, Medium은 2건까지 보여준다(요청된 구성).
    private var visibleItems: [DDayHomeWidgetItem] {
        let limit = family == .systemSmall ? 1 : 2
        return Array(entry.items.prefix(limit))
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                DDayHomeEmptyView()
            } else if family == .systemSmall, let item = visibleItems.first {
                DDayHomeSmallContent(item: item)
            } else {
                DDayHomeMediumContent(items: visibleItems)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        .widgetURL(
            visibleItems.first.map { CalendarWidgetDeepLink.dayURL(for: $0.startDate) }
        )
    }
}

/// D-Day 일정이 없을 때의 안내 문구(빈 화면 대신). Small/Medium 모두 같은 내용을 쓰며,
/// 위젯 전체를 채워 어느 크기에서도 어색하게 치우쳐 보이지 않게 한다.
private struct DDayHomeEmptyView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "flag")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("D-Day 일정 없음")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small: 제목·D-Day 숫자·날짜 정보를 세로로 균형 있게 배치한다(Spacer로 위아래 여백을
/// 나눠, 내용이 위쪽에만 몰리지 않고 위젯 세로 공간 전체를 쓰게 한다). D-Day 숫자가 가장
/// 도드라지도록 가장 크게 그린다.
private struct DDayHomeSmallContent: View {
    let item: DDayHomeWidgetItem

    private var dateText: String {
        item.startDate.formatted(
            Date.FormatStyle()
                .month(.abbreviated)
                .day()
                .locale(Locale.current)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleText
                // Step 5-2 실기기 수정: 가독성을 위해 1~2pt 키운다(.subheadline → 17pt).
                // D-Day 숫자 크기·레이아웃 여백은 그대로 유지한다.
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Text(DDayCalculator.displayText(forDaysRemaining: item.daysRemaining))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 4)

            Text(dateText)
                // .caption2(11pt) → 13pt로 키운다(제목과 동일한 비율로 확대).
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
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
}

/// Medium: 가까운 D-Day 일정 2건을 40:60 비율의 두 열로 보여준다.
private struct DDayHomeMediumContent: View {
    let items: [DDayHomeWidgetItem]

    var body: some View {
        GeometryReader { proxy in
            let separatorHeight: CGFloat = items.count > 1 ? 1 : 0
            let rowHeight = items.count > 1
                ? max((proxy.size.height - separatorHeight) / 2, 0)
                : proxy.size.height

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 0) {
                        // 아래쪽 일정은 하단에 정렬
                        if items.count == 1 || index > 0 {
                            Spacer(minLength: 0)
                        }

                        DDayHomeMediumRow(
                            item: item,
                            leftColumnWidth: proxy.size.width * 0.4
                        )

                        // 위쪽 일정은 상단에 정렬
                        if items.count == 1 || index == 0 {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(
                        width: proxy.size.width,
                        height: rowHeight
                    )

                    if index < items.count - 1 {
                        Divider()
                            .frame(height: separatorHeight)
                            .overlay(Color.gray.opacity(0.35))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}

/// Medium 한 행을 D-Day 40%, 일정 정보 60%로 나눠 표시한다.
private struct DDayHomeMediumRow: View {
    let item: DDayHomeWidgetItem
    let leftColumnWidth: CGFloat

    private var dateText: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: item.startDate)
        return String(
            format: "%04d.%02d.%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(DDayCalculator.displayText(forDaysRemaining: item.daysRemaining))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: leftColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                titleText
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(dateText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
}

#Preview("D-Day Small", as: .systemSmall) {
    DDayHomeWidget()
} timeline: {
    DDayHomeWidgetEntry.placeholder
    DDayHomeWidgetEntry.empty(for: .now)
}

#Preview("D-Day Medium", as: .systemMedium) {
    DDayHomeWidget()
} timeline: {
    DDayHomeWidgetEntry.placeholder
}
