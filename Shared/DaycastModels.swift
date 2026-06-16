import Foundation

struct DaycastEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let time: String
    let location: String?
    let isAllDay: Bool

    init(id: UUID = UUID(), title: String, time: String, location: String? = nil, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.time = time
        self.location = location
        self.isAllDay = isAllDay
    }
}

struct DaycastWeather: Codable, Hashable {
    let condition: String
    let temperature: Int
    let high: Int
    let low: Int
    let precipitationChance: Int
    let sunrise: Date?
    let sunset: Date?
    /// True for stub weather that's been substituted because we have no real
    /// data yet (e.g. before the first successful sync). Lets the UI render
    /// the "open Daycast to sync" copy without doing string comparisons on
    /// `condition` like the previous `"Weather soon"` sentinel.
    let isPlaceholder: Bool

    init(
        condition: String,
        temperature: Int,
        high: Int,
        low: Int,
        precipitationChance: Int,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        isPlaceholder: Bool = false
    ) {
        self.condition = condition
        self.temperature = temperature
        self.high = high
        self.low = low
        self.precipitationChance = precipitationChance
        self.sunrise = sunrise
        self.sunset = sunset
        self.isPlaceholder = isPlaceholder
    }
}

struct DaycastDay: Codable, Hashable {
    let label: String
    let dateLine: String
    let weather: DaycastWeather
    let events: [DaycastEvent]
    let focusWindow: String
    let nudge: String
}

struct DaycastWidgetBackground: Codable, Hashable {
    enum Style: String, Codable {
        case solid
        case glass
    }

    let style: Style
    let red: Double
    let green: Double
    let blue: Double

    init(style: Style, red: Double, green: Double, blue: Double) {
        self.style = style
        self.red = red
        self.green = green
        self.blue = blue
    }

    static let wallpaperPaper = DaycastWidgetBackground(
        style: .solid,
        red: 0.957,
        green: 0.867,
        blue: 0.788
    )

    static let glass = DaycastWidgetBackground(
        style: .glass,
        red: 0.957,
        green: 0.867,
        blue: 0.788
    )
}

struct DaycastSnapshot: Codable, Hashable {
    let today: DaycastDay
    let tomorrow: DaycastDay
    let background: DaycastWidgetBackground

    init(
        today: DaycastDay,
        tomorrow: DaycastDay,
        background: DaycastWidgetBackground = .wallpaperPaper
    ) {
        self.today = today
        self.tomorrow = tomorrow
        self.background = background
    }

    enum CodingKeys: String, CodingKey {
        case today
        case tomorrow
        case background
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decode(DaycastDay.self, forKey: .today)
        tomorrow = try container.decode(DaycastDay.self, forKey: .tomorrow)
        background = try container.decodeIfPresent(DaycastWidgetBackground.self, forKey: .background) ?? .wallpaperPaper
    }

    func applying(todayWeather: DaycastWeather, tomorrowWeather: DaycastWeather) -> DaycastSnapshot {
        DaycastSnapshot(
            today: DaycastDay(
                label: today.label,
                dateLine: today.dateLine,
                weather: todayWeather,
                events: today.events,
                focusWindow: today.focusWindow,
                nudge: today.nudge
            ),
            tomorrow: DaycastDay(
                label: tomorrow.label,
                dateLine: tomorrow.dateLine,
                weather: tomorrowWeather,
                events: tomorrow.events,
                focusWindow: tomorrow.focusWindow,
                nudge: tomorrow.nudge
            ),
            background: background
        )
    }

    func applying(background: DaycastWidgetBackground) -> DaycastSnapshot {
        DaycastSnapshot(
            today: today,
            tomorrow: tomorrow,
            background: background
        )
    }

    static let preview = DaycastSnapshot(
        today: DaycastDay(
            label: "Today",
            dateLine: "Today",
            weather: DaycastWeather(
                condition: "Weather soon",
                temperature: 0,
                high: 0,
                low: 0,
                precipitationChance: 0,
                isPlaceholder: true
            ),
            events: [],
            focusWindow: "Sync Calendar",
            nudge: "Open Daycast to sync"
        ),
        tomorrow: DaycastDay(
            label: "Tomorrow",
            dateLine: "Tomorrow",
            weather: DaycastWeather(
                condition: "Weather soon",
                temperature: 0,
                high: 0,
                low: 0,
                precipitationChance: 0,
                isPlaceholder: true
            ),
            events: [],
            focusWindow: "Sync Calendar",
            nudge: "No synced events yet"
        )
    )

    static let unavailable = DaycastSnapshot(
        today: DaycastDay(
            label: "Today",
            dateLine: "No shared file",
            weather: DaycastWeather(
                condition: "Weather soon",
                temperature: 0,
                high: 0,
                low: 0,
                precipitationChance: 0,
                isPlaceholder: true
            ),
            events: [],
            focusWindow: "Open Daycast",
            nudge: "Widget cannot read sync file"
        ),
        tomorrow: DaycastDay(
            label: "Tomorrow",
            dateLine: "No shared file",
            weather: DaycastWeather(
                condition: "Weather soon",
                temperature: 0,
                high: 0,
                low: 0,
                precipitationChance: 0,
                isPlaceholder: true
            ),
            events: [],
            focusWindow: "Open Daycast",
            nudge: "Widget cannot read sync file"
        )
    )
}
