import AppKit
import SwiftUI

@main
struct RenderDaycastWidget {
    @MainActor
    static func main() throws {
        let snapshotURL = URL(fileURLWithPath: "/Users/josh/Library/Group Containers/H9GD4A7SQF.com.example.daycast.shared/DaycastSnapshot.json")
        let isBusyPreview = CommandLine.arguments.contains("--busy")
        let isMonoPreview = ProcessInfo.processInfo.environment["DAYCAST_MONO_RENDER"] == "1"
        let outputStem = isBusyPreview ? "daycast-widget-busy-render" : "daycast-widget-render"
        let outputName = ProcessInfo.processInfo.environment["DAYCAST_RENDER_NAME"]
            ?? (isMonoPreview ? "\(outputStem)-mono.png" : "\(outputStem).png")
        let outputURL = URL(fileURLWithPath: "/Users/josh/Projects/Widgets/.daycast-shots/\(outputName)")

        let data = try Data(contentsOf: snapshotURL)
        let syncedSnapshot = try JSONDecoder().decode(DaycastSnapshot.self, from: data)
        if CommandLine.arguments.contains("--weather-matrix") {
            let outputURL = URL(fileURLWithPath: "/Users/josh/Projects/Widgets/.daycast-shots/daycast-widget-weather-matrix.png")
            try renderWeatherMatrix(from: syncedSnapshot, to: outputURL)
            print(outputURL.path)
            return
        }

        let snapshot = isBusyPreview ? syncedSnapshot.busyPreview : syncedSnapshot
        let palette = DaycastPalette.palette(for: snapshot.themePhase(at: Date()), background: snapshot.background)

        let content = ExtraLargePosterLayout(snapshot: snapshot)
            .frame(width: 720, height: 338)
            .foregroundStyle(palette.ink)
            .environment(\.daycastPalette, palette)
            .background(
                PosterBackground(weather: snapshot.today.weather)
                    .environment(\.daycastPalette, palette)
            )

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw RenderError.failedToCreateImage
        }

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: outputURL, options: [.atomic])
        print(outputURL.path)
    }

    @MainActor
    static func renderWeatherMatrix(from snapshot: DaycastSnapshot, to outputURL: URL) throws {
        let pairs = [
            (
                DaycastWeather(condition: "Clear", temperature: 18, high: 21, low: 11, precipitationChance: 3),
                DaycastWeather(condition: "Cloudy", temperature: 9, high: 13, low: 8, precipitationChance: 93)
            ),
            (
                DaycastWeather(condition: "Partly cloudy", temperature: 15, high: 18, low: 9, precipitationChance: 12),
                DaycastWeather(condition: "Drizzle", temperature: 15, high: 15, low: 8, precipitationChance: 100)
            ),
            (
                DaycastWeather(condition: "Rain", temperature: 11, high: 14, low: 7, precipitationChance: 88),
                DaycastWeather(condition: "Showers", temperature: 12, high: 16, low: 6, precipitationChance: 61)
            ),
            (
                DaycastWeather(condition: "Snow", temperature: -1, high: 2, low: -4, precipitationChance: 72),
                DaycastWeather(condition: "Fog", temperature: 6, high: 9, low: 3, precipitationChance: 18)
            ),
            (
                DaycastWeather(condition: "Thunderstorm", temperature: 17, high: 20, low: 13, precipitationChance: 84),
                DaycastWeather(condition: "Weather soon", temperature: 0, high: 0, low: 0, precipitationChance: 0)
            )
        ]

        let content = VStack(spacing: 18) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                let matrixSnapshot = snapshot.applying(todayWeather: pair.0, tomorrowWeather: pair.1)
                let palette = DaycastPalette.palette(
                    for: matrixSnapshot.themePhase(at: Date()),
                    background: matrixSnapshot.background
                )

                ExtraLargePosterLayout(snapshot: matrixSnapshot)
                    .frame(width: 720, height: 338)
                    .foregroundStyle(palette.ink)
                    .environment(\.daycastPalette, palette)
                    .background(
                        PosterBackground(weather: pair.0)
                            .environment(\.daycastPalette, palette)
                    )
            }
        }
        .padding(24)
        .background(Color(red: 0.957, green: 0.867, blue: 0.788))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw RenderError.failedToCreateImage
        }

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: outputURL, options: [.atomic])
    }
}

enum RenderError: Error {
    case failedToCreateImage
}

private extension DaycastSnapshot {
    var busyPreview: DaycastSnapshot {
        DaycastSnapshot(
            today: DaycastDay(
                label: today.label,
                dateLine: today.dateLine,
                weather: today.weather,
                events: [
                    DaycastEvent(title: "Morning planning", time: "09:00"),
                    DaycastEvent(title: "Design review", time: "11:30"),
                    DaycastEvent(title: "Lunch with Sam", time: "13:00"),
                    DaycastEvent(title: "Project sync", time: "16:15")
                ],
                focusWindow: "Busy until 17:00",
                nudge: today.nudge
            ),
            tomorrow: DaycastDay(
                label: tomorrow.label,
                dateLine: tomorrow.dateLine,
                weather: tomorrow.weather,
                events: tomorrow.events + [
                    DaycastEvent(title: "Prep notes", time: "10:00"),
                    DaycastEvent(title: "Evening reminder", time: "18:30")
                ],
                focusWindow: tomorrow.focusWindow,
                nudge: tomorrow.nudge
            )
        )
    }
}
