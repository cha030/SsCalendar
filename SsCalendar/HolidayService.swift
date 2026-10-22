import Foundation

@MainActor
final class HolidayService {
    static let shared = HolidayService()

    private static let endpoint = URL(
        string: "https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo"
    )

    private let session: URLSession
    private var cache: [String: [Holiday]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func holidays(
        for month: HolidayMonth,
        country: HolidayCountry
    ) async throws -> [Holiday] {
        let cacheKey = "\(country.rawValue)-\(month.year)-\(month.month)"
        if let cachedHolidays = cache[cacheKey] {
            return cachedHolidays
        }

        if country == .unitedStates {
            let holidays = USFederalHolidayCalculator.records(for: month).map {
                Holiday(
                    year: $0.year,
                    month: $0.month,
                    day: $0.day,
                    name: $0.name,
                    isHoliday: $0.isHoliday
                )
            }
            cache[cacheKey] = holidays
            updateSharedCache(with: holidays, for: month, country: country)
            return holidays
        }

        guard let apiKey = AppConfig.holidayAPIKey else {
            throw HolidayServiceError.missingAPIKey
        }

        guard var components = Self.endpoint.flatMap({
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }) else {
            throw HolidayServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "ServiceKey", value: apiKey),
            URLQueryItem(name: "solYear", value: String(month.year)),
            URLQueryItem(
                name: "solMonth",
                value: String(format: "%02d", month.month)
            ),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "numOfRows", value: "100")
        ]

        guard let url = components.url else {
            throw HolidayServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard
            let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            throw HolidayServiceError.invalidResponse
        }

        let parserDelegate = HolidayResponseParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate

        guard parser.parse() else {
            throw HolidayServiceError.parsingFailed(
                parser.parserError?.localizedDescription
            )
        }

        guard parserDelegate.resultCode == "00" else {
            throw HolidayServiceError.apiError(
                code: parserDelegate.resultCode ?? "UNKNOWN",
                message: parserDelegate.resultMessage ?? ""
            )
        }

        let holidays = parserDelegate.items.compactMap {
            makeHoliday(from: $0)
        }
        cache[cacheKey] = holidays
        updateSharedCache(with: holidays, for: month, country: country)
        return holidays
    }

    private func updateSharedCache(
        with holidays: [Holiday],
        for month: HolidayMonth,
        country: HolidayCountry
    ) {
        let records = holidays.map {
            SharedHolidayRecord(
                year: $0.year,
                month: $0.month,
                day: $0.day,
                name: $0.name,
                isHoliday: $0.isHoliday
            )
        }

        guard let changed = try? SharedHolidayCache.store(
            records,
            country: country,
            year: month.year,
            month: month.month
        ), changed else {
            return
        }

        WidgetReloadManager.reloadCalendar()
    }

    private func makeHoliday(
        from item: HolidayResponseItem
    ) -> Holiday? {
        guard item.isHoliday == "Y", let components = Self.dateComponents(from: item.locationDate) else {
            return nil
        }

        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else { return nil }

        return Holiday(year: year, month: month, day: day, name: item.name, isHoliday: true)
    }

    nonisolated static func dateComponents(from locationDate: String) -> DateComponents? {
        guard
            locationDate.count == 8,
            let year = Int(locationDate.prefix(4)),
            let month = Int(locationDate.dropFirst(4).prefix(2)),
            let day = Int(locationDate.suffix(2))
        else {
            return nil
        }

        return DateComponents(year: year, month: month, day: day)
    }
}

enum HolidayServiceError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case parsingFailed(String?)
    case apiError(code: String, message: String)
}

private struct HolidayResponseItem {
    var locationDate = ""
    var name = ""
    var isHoliday = ""
}

private final class HolidayResponseParser: NSObject, XMLParserDelegate {
    private(set) var resultCode: String?
    private(set) var resultMessage: String?
    private(set) var items: [HolidayResponseItem] = []

    private var currentElement = ""
    private var currentText = ""
    private var currentItem: HolidayResponseItem?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            currentItem = HolidayResponseItem()
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = currentText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        switch elementName {
        case "resultCode":
            resultCode = value
        case "resultMsg":
            resultMessage = value
        case "locdate":
            currentItem?.locationDate = value
        case "dateName":
            currentItem?.name = value
        case "isHoliday":
            currentItem?.isHoliday = value
        case "item":
            if let currentItem {
                items.append(currentItem)
            }
            currentItem = nil
        default:
            break
        }

        currentElement = ""
        currentText = ""
    }
}
