import SwiftUI
import WidgetKit

enum DaycastTypography {
    static var renderFontFamily: String? {
        ProcessInfo.processInfo.environment["DAYCAST_FONT_FAMILY"]
    }

    static var useMono: Bool {
        ProcessInfo.processInfo.environment["DAYCAST_MONO_RENDER"] == "1"
    }

    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        if let renderFontFamily, !renderFontFamily.isEmpty {
            return .custom(renderFontFamily, size: size).weight(weight)
        }

        if useMono {
            return .custom("JetBrainsMono NF", size: size).weight(weight)
        }

        return .system(size: size, weight: weight, design: .default)
    }
}

struct DaycastEntry: TimelineEntry {
    let date: Date
    let snapshot: DaycastSnapshot
}

enum DaycastThemePhase {
    case daylight
    case goldenHour
    case afterSunset
    case lateNight
}

struct DaycastPalette {
    private static let desktopPaper = Color(red: 0.957, green: 0.867, blue: 0.788)
    private static let desktopDivider = Color(red: 0.73, green: 0.62, blue: 0.55)

    let phase: DaycastThemePhase
    let paper: Color
    let backgroundStyle: DaycastWidgetBackground.Style
    let ink: Color
    let secondaryInk: Color
    let divider: Color
    let backgroundLabelOpacity: Double
    let dividerOpacity: Double
    let iconOpacityMultiplier: Double

    static func palette(
        for phase: DaycastThemePhase,
        background: DaycastWidgetBackground = .wallpaperPaper
    ) -> DaycastPalette {
        let paper = Color(red: background.red, green: background.green, blue: background.blue)

        switch phase {
        case .daylight:
            return DaycastPalette(
                phase: phase,
                paper: paper,
                backgroundStyle: background.style,
                ink: Color(red: 0.07, green: 0.08, blue: 0.09),
                secondaryInk: Color(red: 0.30, green: 0.36, blue: 0.36),
                divider: desktopDivider,
                backgroundLabelOpacity: 0.075,
                dividerOpacity: 0.42,
                iconOpacityMultiplier: 1.0
            )
        case .goldenHour:
            return DaycastPalette(
                phase: phase,
                paper: paper,
                backgroundStyle: background.style,
                ink: Color(red: 0.12, green: 0.10, blue: 0.08),
                secondaryInk: Color(red: 0.38, green: 0.31, blue: 0.24),
                divider: desktopDivider,
                backgroundLabelOpacity: 0.085,
                dividerOpacity: 0.42,
                iconOpacityMultiplier: 1.12
            )
        case .afterSunset:
            return DaycastPalette(
                phase: phase,
                paper: paper,
                backgroundStyle: background.style,
                ink: Color(red: 0.08, green: 0.12, blue: 0.13),
                secondaryInk: Color(red: 0.24, green: 0.31, blue: 0.32),
                divider: desktopDivider,
                backgroundLabelOpacity: 0.095,
                dividerOpacity: 0.42,
                iconOpacityMultiplier: 1.18
            )
        case .lateNight:
            return DaycastPalette(
                phase: phase,
                paper: paper,
                backgroundStyle: background.style,
                ink: Color(red: 0.10, green: 0.12, blue: 0.12),
                secondaryInk: Color(red: 0.30, green: 0.36, blue: 0.36),
                divider: desktopDivider,
                backgroundLabelOpacity: 0.075,
                dividerOpacity: 0.42,
                iconOpacityMultiplier: 1.24
            )
        }
    }

    func tint(clear color: Color) -> Color {
        switch phase {
        case .daylight:
            return color
        case .goldenHour:
            return Color(red: 0.47, green: 0.36, blue: 0.22)
        case .afterSunset:
            return Color(red: 0.29, green: 0.43, blue: 0.48)
        case .lateNight:
            return Color(red: 0.48, green: 0.64, blue: 0.67)
        }
    }

    func temperatureTint(clear color: Color) -> Color {
        switch phase {
        case .daylight:
            return color
        case .goldenHour:
            return Color(red: 0.30, green: 0.23, blue: 0.15)
        case .afterSunset:
            return Color(red: 0.13, green: 0.22, blue: 0.25)
        case .lateNight:
            return Color(red: 0.72, green: 0.80, blue: 0.78)
        }
    }

    func heroIconOpacity(base: Double) -> Double {
        switch backgroundStyle {
        case .solid:
            return base * iconOpacityMultiplier
        case .glass:
            return min(0.54, base * iconOpacityMultiplier * 2.7)
        }
    }
}

private struct DaycastPaletteKey: EnvironmentKey {
    static let defaultValue = DaycastPalette.palette(for: .daylight)
}

extension EnvironmentValues {
    var daycastPalette: DaycastPalette {
        get { self[DaycastPaletteKey.self] }
        set { self[DaycastPaletteKey.self] = newValue }
    }
}

private extension Image {
    @ViewBuilder
    func daycastFullColorWidgetRendering() -> some View {
        if #available(macOS 15.0, *) {
            widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}

struct DaycastProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaycastEntry {
        DaycastEntry(date: Date(), snapshot: DaycastStore.loadSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (DaycastEntry) -> Void) {
        completion(DaycastEntry(date: Date(), snapshot: DaycastStore.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaycastEntry>) -> Void) {
        let now = Date()
        let snapshot = DaycastStore.loadSnapshot()
        // Emit one entry per phase boundary (sunrise / golden hour / sunset /
        // late night) for both today and tomorrow. WidgetKit will roll to the
        // right entry on its own when the wall clock crosses each boundary, so
        // we don't need a full provider call to repaint the theme.
        let entryDates = [now] + snapshot.themePhaseBoundaryDates(after: now)
        let entries = entryDates.map { DaycastEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct DaycastWidgetView: View {
    let entry: DaycastEntry

    var body: some View {
        let palette = DaycastPalette.palette(
            for: entry.snapshot.themePhase(at: entry.date),
            background: entry.snapshot.background
        )

        GeometryReader { _ in
            ExtraLargePosterLayout(snapshot: entry.snapshot)
            .foregroundStyle(palette.ink)
            .widgetAccentable(false)
            .environment(\.daycastPalette, palette)
            .containerBackground(for: .widget) {
                PosterBackground(weather: entry.snapshot.today.weather)
                    .environment(\.daycastPalette, palette)
            }
        }
    }
}

struct ExtraLargePosterLayout: View {
    let snapshot: DaycastSnapshot
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        let metrics = PosterMetrics()

        ZStack(alignment: .topLeading) {
            BackgroundDayLabelLayer(
                today: snapshot.today,
                tomorrow: snapshot.tomorrow,
                metrics: metrics
            )

            GeometryReader { proxy in
                let dividerX = metrics.padding + ((proxy.size.width - metrics.padding - 1) / 2)

                Rule(weight: 2, color: palette.divider.opacity(palette.dividerOpacity), vertical: true)
                    .frame(height: proxy.size.height)
                    .position(x: dividerX, y: proxy.size.height / 2)
            }
            .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 0) {
                ExtraLargeDayPanel(
                    day: snapshot.today,
                    metrics: metrics,
                    isPrimary: true
                )
                .padding(.trailing, metrics.columnGap)
                .clipped()

                Color.clear
                    .frame(width: 2)

                ExtraLargeDayPanel(
                    day: snapshot.tomorrow,
                    metrics: metrics,
                    isPrimary: false
                )
                .padding(.leading, metrics.columnGap)
                .clipped()
            }
            .padding(.init(top: 0, leading: metrics.padding, bottom: metrics.padding, trailing: 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct BackgroundDayLabelLayer: View {
    let today: DaycastDay
    let tomorrow: DaycastDay
    let metrics: PosterMetrics
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let dividerX = metrics.padding + ((proxy.size.width - metrics.padding - 1) / 2)

            HStack(alignment: .top, spacing: 0) {
                backgroundLabel(today, isPrimary: true)
                    .frame(width: dividerX, height: proxy.size.height, alignment: .bottomLeading)
                    .clipped()

                backgroundLabel(tomorrow, isPrimary: false)
                    .frame(
                        width: proxy.size.width - dividerX,
                        height: proxy.size.height,
                        alignment: .bottomLeading
                    )
                    .clipped()
            }
        }
        .allowsHitTesting(false)
    }

    private func backgroundLabel(_ day: DaycastDay, isPrimary: Bool) -> some View {
        Text(day.label.uppercased())
            .font(DaycastTypography.font(size: metrics.backgroundLabelSize, weight: .black))
            .foregroundStyle(palette.ink.opacity(palette.backgroundLabelOpacity))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(x: day.backgroundLabelWidthScale, y: 1.0, anchor: .leading)
            .offset(day.backgroundLabelOffset(metrics: metrics, isPrimary: isPrimary))
    }
}

struct ExtraLargeDayPanel: View {
    let day: DaycastDay
    let metrics: PosterMetrics
    let isPrimary: Bool
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeatherHeroSymbol(weather: day.weather, metrics: metrics)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, metrics.iconTopInset)
                .padding(.trailing, isPrimary ? -66 : -48)

            VStack {
                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)

                    Text(day.dateLine)
                        .font(DaycastTypography.font(size: metrics.dateSize, weight: .semibold))
                        .foregroundStyle(day.weather.temperatureColor(in: palette).opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.trailing, isPrimary ? metrics.dateRightInset : metrics.foregroundTrailingPadding + metrics.dateRightInset)
            .padding(.bottom, metrics.dateBottomInset)
            .zIndex(2)

            VStack(alignment: .leading, spacing: metrics.panelGap) {
                HStack(alignment: .top, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(day.weather.hasWeather ? "\(day.weather.temperature)" : "--")
                            .font(DaycastTypography.font(size: metrics.temperatureSize, weight: .bold))
                            .foregroundStyle(day.weather.temperatureColor(in: palette).opacity(0.88))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.54)

                        Text("°C")
                            .font(DaycastTypography.font(size: metrics.degreeSize, weight: .semibold))
                            .foregroundStyle(day.weather.temperatureColor(in: palette).opacity(0.76))
                            .baselineOffset(metrics.degreeOffset)
                    }

                    Spacer(minLength: 8)
                }
                .frame(height: metrics.heroHeight, alignment: .topLeading)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(day.weather.condition)
                        .font(DaycastTypography.font(size: metrics.conditionSize, weight: .bold))
                        .foregroundStyle(day.weather.accentColor(in: palette))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 8)

                    HighLowTemperatureLine(weather: day.weather, metrics: metrics)

                    WeatherStatLine(
                        symbol: day.weather.precipitationChance > 50 ? "cloud.rain.fill" : "drop.fill",
                        value: day.weather.hasWeather ? "\(day.weather.precipitationChance)%" : "Sync",
                        metrics: metrics
                    )
                }
                .frame(height: metrics.conditionHeight, alignment: .center)
                .zIndex(1)

                Rule(weight: 2, color: day.weather.accentColor(in: palette).opacity(isPrimary ? 0.9 : 0.55))

                VStack(alignment: .leading, spacing: metrics.agendaGap) {
                    let visibleEvents = Array(day.events.prefix(3))
                    let remainingEvents = max(0, day.events.count - visibleEvents.count)
                    let titleLineLimit = visibleEvents.count == 1 && remainingEvents == 0 ? 2 : 1

                    if visibleEvents.isEmpty {
                        EmptyAgendaLine(text: day.focusWindow, metrics: metrics, accent: day.weather.accentColor(in: palette))
                    } else {
                        ForEach(visibleEvents) { event in
                            AgendaLine(
                                event: event,
                                metrics: metrics,
                                accent: day.weather.accentColor(in: palette),
                                titleLineLimit: titleLineLimit
                            )
                        }

                        if remainingEvents > 0 {
                            MoreEventsLine(count: remainingEvents, metrics: metrics, accent: day.weather.accentColor(in: palette))
                        }
                    }
                }
                .frame(height: metrics.agendaHeight, alignment: .topLeading)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Rectangle()
                        .fill(day.weather.accentColor(in: palette))
                        .frame(width: 18, height: 3)

                    Text(day.focusWindow)
                        .font(DaycastTypography.font(size: metrics.smallMetaSize, weight: .semibold))
                        .foregroundStyle(palette.secondaryInk.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.bottom, 8)
            }
            .padding(.trailing, isPrimary ? 0 : metrics.foregroundTrailingPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WeatherHeroSymbol: View {
    let weather: DaycastWeather
    let metrics: PosterMetrics
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        Image(systemName: weather.symbolName)
            .daycastFullColorWidgetRendering()
            .font(.system(size: metrics.iconSize * weather.heroSymbolScale, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(weather.accentColor(in: palette).opacity(palette.heroIconOpacity(base: metrics.iconOpacity)))
            .frame(width: metrics.iconFrame, height: metrics.iconFrame, alignment: .center)
            .offset(weather.heroSymbolOffset)
    }
}

struct PosterHeader: View {
    let today: DaycastDay
    let tomorrow: DaycastDay
    let metrics: PosterMetrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.columnGap) {
            VStack(alignment: .leading, spacing: metrics.heroGap) {
                Text(today.dateLine)
                    .font(.system(size: metrics.dateSize, weight: .semibold, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(today.weather.hasWeather ? "\(today.weather.temperature)" : "--")
                        .font(.system(size: metrics.temperatureSize, weight: .regular, design: .serif))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text("°C")
                        .font(.system(size: metrics.degreeSize, weight: .regular, design: .serif))
                        .baselineOffset(metrics.degreeOffset)
                }

                Text(today.weather.condition)
                    .font(.system(size: metrics.conditionSize, weight: .semibold, design: .default))
                    .foregroundStyle(today.weather.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: metrics.metaGap) {
                Image(systemName: today.weather.symbolName)
                    .daycastFullColorWidgetRendering()
                    .font(.system(size: metrics.iconSize, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(today.weather.accentColor)
                    .frame(width: metrics.iconFrame, height: metrics.iconFrame, alignment: .topTrailing)

                WeatherStatLine(
                    symbol: "arrow.up.and.down",
                    value: today.weather.hasWeather ? "\(today.weather.high)°/\(today.weather.low)°" : "--",
                    metrics: metrics
                )

                WeatherStatLine(
                    symbol: today.weather.precipitationChance > 50 ? "cloud.rain.fill" : "drop.fill",
                    value: today.weather.hasWeather ? "\(today.weather.precipitationChance)% rain" : "Sync weather",
                    metrics: metrics
                )

                WeatherStatLine(
                    symbol: "calendar",
                    value: "\(tomorrow.events.count) tomorrow",
                    metrics: metrics
                )
            }
        }
    }
}

struct WeatherStatLine: View {
    let symbol: String
    let value: String
    let metrics: PosterMetrics
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(DaycastTypography.font(size: metrics.statSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Image(systemName: symbol)
                .daycastFullColorWidgetRendering()
                .font(.system(size: metrics.statIconSize, weight: .heavy))
                .frame(width: metrics.statIconSize + 3)
        }
        .foregroundStyle(palette.secondaryInk.opacity(0.9))
    }
}

struct HighLowTemperatureLine: View {
    let weather: DaycastWeather
    let metrics: PosterMetrics

    private let highColor = Color(red: 0.86, green: 0.39, blue: 0.36)
    private let lowColor = Color(red: 0.36, green: 0.55, blue: 0.82)

    var body: some View {
        HStack(spacing: 9) {
            temperatureItem(
                symbol: "arrow.up",
                value: weather.hasWeather ? "\(weather.high)°" : "--",
                color: highColor
            )

            temperatureItem(
                symbol: "arrow.down",
                value: weather.hasWeather ? "\(weather.low)°" : "--",
                color: lowColor
            )
        }
    }

    private func temperatureItem(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .daycastFullColorWidgetRendering()
                .font(.system(size: metrics.statIconSize - 1, weight: .heavy))
                .foregroundStyle(color.opacity(0.98))
                .frame(width: metrics.statIconSize)

            Text(value)
                .font(DaycastTypography.font(size: metrics.statSize, weight: .semibold))
                .foregroundStyle(color.opacity(0.98))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct AgendaColumn: View {
    let day: DaycastDay
    let maxEvents: Int
    let metrics: PosterMetrics
    let isPrimary: Bool
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.agendaGap) {
            HStack(alignment: .lastTextBaseline) {
                Text(day.label)
                    .font(.system(size: metrics.dayLabelSize, weight: .semibold, design: .default))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(day.dateLine)
                    .font(.system(size: metrics.smallMetaSize, weight: .medium, design: .default))
                    .foregroundStyle(palette.secondaryInk.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            let visibleEvents = Array(day.events.prefix(maxEvents))

            if visibleEvents.isEmpty {
                EmptyAgendaLine(text: day.focusWindow, metrics: metrics, accent: isPrimary ? day.weather.accentColor(in: palette) : palette.secondaryInk.opacity(0.85))
            } else {
                ForEach(visibleEvents) { event in
                    AgendaLine(event: event, metrics: metrics, accent: isPrimary ? day.weather.accentColor(in: palette) : palette.secondaryInk.opacity(0.85))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: day.weather.symbolName)
                    .daycastFullColorWidgetRendering()
                    .font(.system(size: metrics.footerIconSize, weight: .bold))
                    .foregroundStyle(day.weather.accentColor(in: palette))

                Text(day.focusWindow)
                    .font(.system(size: metrics.smallMetaSize, weight: .medium, design: .default))
                    .foregroundStyle(palette.secondaryInk.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AgendaLine: View {
    let event: DaycastEvent
    let metrics: PosterMetrics
    let accent: Color
    var titleLineLimit = 1
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.eventGap) {
           Text(event.time)
                .font(DaycastTypography.font(size: metrics.timeSize, weight: .semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .frame(width: metrics.timeWidth, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(event.title)
                .font(DaycastTypography.font(size: metrics.eventTitleSize, weight: .medium))
                .foregroundStyle(palette.ink.opacity(0.86))
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, metrics.eventVerticalPadding)
    }
}

struct MoreEventsLine: View {
    let count: Int
    let metrics: PosterMetrics
    let accent: Color
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        HStack(spacing: metrics.eventGap) {
            Text("+")
                .font(DaycastTypography.font(size: metrics.timeSize, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: metrics.timeWidth, alignment: .leading)

            Text("\(count) more")
                .font(DaycastTypography.font(size: metrics.eventTitleSize, weight: .semibold))
                .foregroundStyle(palette.secondaryInk.opacity(0.88))
                .lineLimit(1)
        }
        .padding(.vertical, metrics.eventVerticalPadding)
    }
}

struct EmptyAgendaLine: View {
    let text: String
    let metrics: PosterMetrics
    let accent: Color
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        HStack(spacing: metrics.eventGap) {
            Text("--")
                .font(DaycastTypography.font(size: metrics.timeSize, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: metrics.timeWidth, alignment: .leading)

            Text(text)
                .font(DaycastTypography.font(size: metrics.eventTitleSize, weight: .medium))
                .foregroundStyle(palette.secondaryInk.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, metrics.eventVerticalPadding)
    }
}

struct Rule: View {
    let weight: CGFloat
    let color: Color
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? weight : nil, height: vertical ? nil : weight)
    }
}

struct PosterBackground: View {
    let weather: DaycastWeather
    @Environment(\.daycastPalette) private var palette

    var body: some View {
        switch palette.backgroundStyle {
        case .solid:
            palette.paper
        case .glass:
            GlassWidgetBackground()
        }
    }
}

struct GlassWidgetBackground: View {
    var body: some View {
        Color.clear
    }
}

struct PosterMetrics {
    let padding: CGFloat = 18
    let sectionGap: CGFloat = 18
    let columnGap: CGFloat = 22
    let panelGap: CGFloat = 5
    let heroGap: CGFloat = 4
    let metaGap: CGFloat = 11
    let agendaGap: CGFloat = 7
    let eventGap: CGFloat = 11
    let eventVerticalPadding: CGFloat = 1
    let dateRightInset: CGFloat = 10
    let dateBottomInset: CGFloat = 8
    let heroHeight: CGFloat = 128
    let conditionHeight: CGFloat = 30
    let agendaHeight: CGFloat = 84
    let iconTopInset: CGFloat = -56
    let foregroundTrailingPadding: CGFloat = 22

    let dayTitleSize: CGFloat = 34
    let dateSize: CGFloat = 18
    let temperatureSize: CGFloat = 128
    let degreeSize: CGFloat = 86
    let degreeOffset: CGFloat = 21
    let conditionSize: CGFloat = 22
    let iconSize: CGFloat = 186
    let iconFrame: CGFloat = 232
    let iconOpacity: Double = 0.18
    let statSize: CGFloat = 16
    let statIconSize: CGFloat = 14
    let dayLabelSize: CGFloat = 26
    let smallMetaSize: CGFloat = 14
    let timeSize: CGFloat = 18
    let timeWidth: CGFloat = 64
    let eventTitleSize: CGFloat = 17
    let footerIconSize: CGFloat = 15
    let backgroundLabelSize: CGFloat = 112
}

extension DaycastWeather {
    var hasWeather: Bool {
        !isPlaceholder
    }

    var symbolName: String {
        switch condition.lowercased() {
        case let value where value.contains("clear"):
            return "sun.max.fill"
        case let value where value.contains("partly"):
            return "cloud.fill"
        case let value where value.contains("fog"):
            return "cloud.fog.fill"
        case let value where value.contains("drizzle"):
            return "cloud.drizzle.fill"
        case let value where value.contains("rain") || value.contains("showers"):
            return "cloud.rain.fill"
        case let value where value.contains("snow"):
            return "cloud.snow.fill"
        case let value where value.contains("storm") || value.contains("thunder"):
            return "cloud.bolt.rain.fill"
        case let value where value.contains("cloud"):
            return "cloud.fill"
        default:
            return "cloud.fill"
        }
    }

    var accentColor: Color {
        accentColor(in: .palette(for: .daylight))
    }

    func accentColor(in palette: DaycastPalette) -> Color {
        switch condition.lowercased() {
        case let value where value.contains("clear"):
            return palette.tint(clear: Color(red: 0.78, green: 0.44, blue: 0.10))
        case let value where value.contains("rain") || value.contains("drizzle") || value.contains("showers"):
            return palette.tint(clear: Color(red: 0.10, green: 0.43, blue: 0.58))
        case let value where value.contains("snow"):
            return palette.tint(clear: Color(red: 0.32, green: 0.54, blue: 0.65))
        case let value where value.contains("storm") || value.contains("thunder"):
            return palette.tint(clear: Color(red: 0.38, green: 0.30, blue: 0.56))
        case let value where value.contains("fog") || value.contains("cloud"):
            return palette.tint(clear: Color(red: 0.43, green: 0.50, blue: 0.52))
        default:
            return palette.tint(clear: Color(red: 0.20, green: 0.48, blue: 0.38))
        }
    }

    var temperatureColor: Color {
        temperatureColor(in: .palette(for: .daylight))
    }

    func temperatureColor(in palette: DaycastPalette) -> Color {
        switch condition.lowercased() {
        case let value where value.contains("clear"):
            return palette.temperatureTint(clear: Color(red: 0.38, green: 0.25, blue: 0.12))
        case let value where value.contains("rain") || value.contains("drizzle") || value.contains("showers"):
            return palette.temperatureTint(clear: Color(red: 0.08, green: 0.25, blue: 0.32))
        case let value where value.contains("snow"):
            return palette.temperatureTint(clear: Color(red: 0.16, green: 0.33, blue: 0.42))
        case let value where value.contains("storm") || value.contains("thunder"):
            return palette.temperatureTint(clear: Color(red: 0.22, green: 0.18, blue: 0.34))
        case let value where value.contains("fog") || value.contains("cloud"):
            return palette.temperatureTint(clear: Color(red: 0.22, green: 0.29, blue: 0.30))
        default:
            return palette.temperatureTint(clear: Color(red: 0.12, green: 0.29, blue: 0.23))
        }
    }

    var heroSymbolScale: CGFloat {
        switch condition.lowercased() {
        case let value where value.contains("clear"):
            return 0.92
        case let value where value.contains("partly"):
            return 1.0
        case let value where value.contains("drizzle"):
            return 1.0
        case let value where value.contains("rain") || value.contains("showers"):
            return 1.0
        case let value where value.contains("snow"):
            return 1.0
        case let value where value.contains("storm") || value.contains("thunder"):
            return 1.0
        case let value where value.contains("fog"):
            return 1.0
        case let value where value.contains("cloud"):
            return 1.0
        default:
            return 1.0
        }
    }

    var heroSymbolOffset: CGSize {
        switch condition.lowercased() {
        case let value where value.contains("clear"):
            return CGSize(width: 4, height: -4)
        case let value where value.contains("partly"):
            return CGSize(width: 0, height: -12)
        case let value where value.contains("drizzle"):
            return CGSize(width: -26, height: 28)
        case let value where value.contains("rain") || value.contains("showers"):
            return CGSize(width: -26, height: 28)
        case let value where value.contains("snow"):
            return CGSize(width: -26, height: 32)
        case let value where value.contains("storm") || value.contains("thunder"):
            return CGSize(width: -26, height: 32)
        case let value where value.contains("fog"):
            return CGSize(width: -18, height: 23)
        case let value where value.contains("cloud"):
            return CGSize(width: 0, height: -12)
        default:
            return CGSize(width: 0, height: -12)
        }
    }

}

extension Color {
    static let daycastPaper = Color(red: 0.75, green: 0.78, blue: 0.74)
    static let daycastInk = Color(red: 0.07, green: 0.08, blue: 0.09)
}

extension DaycastSnapshot {
    /// How far ahead of `date` to look for phase boundaries when building a
    /// timeline. 36h covers today and tomorrow, which is the widget's window.
    static let themePhaseLookahead: TimeInterval = 60 * 60 * 36

    /// Skew applied to boundary comparisons so we never emit an entry whose
    /// date is essentially "now" (rounding in WidgetKit would skip it).
    static let themePhaseRefreshSkew: TimeInterval = 30

    func themePhase(at date: Date) -> DaycastThemePhase {
        guard let sunset = today.weather.sunset else {
            return .daylight
        }

        let goldenHourStart = sunset.addingTimeInterval(-45 * 60)
        let lateNightStart = sunset.addingTimeInterval(4 * 60 * 60)
        let sunrise = today.weather.sunrise

        if let sunrise, date < sunrise {
            return .lateNight
        }

        if date < goldenHourStart {
            return .daylight
        }

        if date < sunset {
            return .goldenHour
        }

        if date < lateNightStart {
            return .afterSunset
        }

        return .lateNight
    }

    /// All theme phase transitions within `lookahead` seconds of `date`,
    /// sorted ascending. Used to build a multi-entry timeline so WidgetKit
    /// can roll between palettes without a fresh provider call.
    func themePhaseBoundaryDates(
        after date: Date,
        lookahead: TimeInterval = DaycastSnapshot.themePhaseLookahead
    ) -> [Date] {
        let candidates = [
            today.weather.sunrise,
            today.weather.sunset?.addingTimeInterval(-45 * 60),
            today.weather.sunset,
            today.weather.sunset?.addingTimeInterval(4 * 60 * 60),
            tomorrow.weather.sunrise,
            tomorrow.weather.sunset?.addingTimeInterval(-45 * 60),
            tomorrow.weather.sunset,
            tomorrow.weather.sunset?.addingTimeInterval(4 * 60 * 60)
        ]

        return candidates
            .compactMap { $0 }
            .filter { $0 > date.addingTimeInterval(DaycastSnapshot.themePhaseRefreshSkew) }
            .filter { $0 < date.addingTimeInterval(lookahead) }
            .sorted()
    }

    func nextThemeRefresh(after date: Date) -> Date? {
        themePhaseBoundaryDates(after: date).first
    }
}

#if !RENDERER
@main
struct DaycastWidgetBundle: WidgetBundle {
    var body: some Widget {
        DaycastWidget()
    }
}
#endif

struct DaycastWidget: Widget {
    let kind = DaycastConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DaycastProvider()) { entry in
            DaycastWidgetView(entry: entry)
        }
        .configurationDisplayName("Daycast Extra Large")
        .description("See today, tomorrow, weather, and your next useful reminder.")
        .supportedFamilies([.systemExtraLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable()
    }
}

extension DaycastDay {
    var backgroundLabelWidthScale: CGFloat {
        1.0
    }

    func backgroundLabelOffset(metrics: PosterMetrics, isPrimary: Bool) -> CGSize {
        isPrimary
            ? CGSize(width: -10, height: 24)
            : CGSize(width: -metrics.columnGap - 6, height: 24)
    }
}

#if DEBUG && !RENDERER
#Preview(as: .systemExtraLarge) {
    DaycastWidget()
} timeline: {
    DaycastEntry(date: Date(), snapshot: .preview)
}
#endif
