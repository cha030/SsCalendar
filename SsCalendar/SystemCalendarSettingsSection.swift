import EventKit
import SwiftUI
import UIKit

/// 설정 화면의 시스템 캘린더 표시 on/off 섹션.
/// 기본값은 OFF이며, 사용자가 켤 때만 Full Access 권한을 요청한다.
struct SystemCalendarSettingsSection: View {
    @AppStorage(
        SystemCalendarService.isEnabledStorageKey,
        store: SystemCalendarService.settingsStore
    ) private var isEnabled = false
    @State private var isRequesting = false
    @State private var isPresentingSelectionIntro = false

    private let service = SystemCalendarService.shared

    var body: some View {
        Section {
            // Form 안의 Section에 붙인 modifier는 행마다 적용되므로, 시트/onAppear는 단일 행인 Toggle에 붙인다.
            Toggle("iPhone 캘린더 일정 표시", isOn: toggleBinding)
                .disabled(isRequesting)
                .onAppear {
                    service.refreshAuthorizationStatus()
                }
                .sheet(isPresented: $isPresentingSelectionIntro) {
                    NavigationStack {
                        SystemCalendarSelectionView(isIntro: true)
                    }
                }

            if isEnabled && service.hasFullAccess {
                NavigationLink {
                    SystemCalendarSelectionView()
                } label: {
                    LabeledContent("표시할 캘린더 선택", value: selectionSummary)
                }
            }

            defaultSaveDestinationSection

            if needsPermissionFromSettings {
                Button("설정 앱에서 권한 허용하기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("캘린더")
        } footer: {
            Text(footerText)
        }
    }

    /// 예: "3/4" (표시 중인 캘린더 수 / 전체 캘린더 수)
    private var selectionSummary: String {
        let calendars = service.calendarGroups().flatMap(\.calendars)
        let visibleCount = calendars.filter { service.isCalendarVisible($0.id) }.count
        return "\(visibleCount)/\(calendars.count)"
    }

    /// 토글은 "사용자가 켰고 실제 권한도 있는 경우"에만 ON으로 보인다.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isEnabled && service.hasFullAccess },
            set: { newValue in
                if newValue {
                    Task { await enable() }
                } else {
                    isEnabled = false
                    WidgetReloadManager.requestCalendarReload()
                }
            }
        )
    }

    private var needsPermissionFromSettings: Bool {
        switch service.authorizationStatus {
        case .denied, .writeOnly:
            return true
        default:
            return false
        }
    }

    private var footerText: String {
        switch service.authorizationStatus {
        case .denied, .writeOnly:
            return String(localized: "캘린더 접근 권한이 없어 iPhone 캘린더 일정을 표시할 수 없습니다. 설정 앱에서 '전체 접근'을 허용해 주세요.")
        case .restricted:
            return String(localized: "이 기기에서는 캘린더 접근이 제한되어 있습니다.")
        default:
            return String(localized: "iCloud, Google, Exchange 등 iPhone에 연결된 캘린더 일정을 함께 표시합니다. 일정을 탭하면 확인하고, 수정 가능한 캘린더의 일정은 수정·삭제할 수 있습니다.")
        }
    }

    @ViewBuilder
    private var defaultSaveDestinationSection: some View {
        LabeledContent("기본 저장 위치", value: "SsCalendar")

        Text("새 일정은 SsCalendar에 저장됩니다. 기존 일정의 저장 위치는 변경되지 않습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }


    private func enable() async {
        isRequesting = true
        let granted = await service.requestFullAccess()
        isEnabled = granted
        WidgetReloadManager.requestCalendarReload()
        isRequesting = false

        // 처음 연동을 켰을 때 한 번만 캘린더 선택 화면을 안내한다(공휴일 중복 해소 안내 포함).
        // "안내 완료" 기록은 안내 화면이 실제로 나타났을 때 SystemCalendarSelectionView가 남긴다.
        if granted && !service.hasShownSelectionIntro {
            isPresentingSelectionIntro = true
        }
    }
}
