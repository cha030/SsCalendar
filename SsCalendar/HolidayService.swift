import Foundation

@MainActor
final class HolidayService {
    static let shared = HolidayService()

    private static let endpoint = URL(
        string: "https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo"
    )

    private let session: URLSession
    private var cache: [HolidayMonth: [Holiday]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func holidays(for month: HolidayMonth) async throws -> [Holiday] {
        if let cachedHolidays = cache[month] {
            return cachedHolidays
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
        cache[month] = holidays
        return holidays
    }

    private func makeHoliday(
        from item: HolidayResponseItem
    ) -> Holiday? {
        guard
            item.isHoliday == "Y",
            item.locationDate.count == 8,
            let year = Int(item.locationDate.prefix(4)),
            let month = Int(item.locationDate.dropFirst(4).prefix(2)),
            let day = Int(item.locationDate.suffix(2))
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

        guard let date = calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        ) else {
            return nil
        }

        return Holiday(
            date: date,
            name: item.name,
            isHoliday: true
        )
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
