import CoreLocation
import Foundation

struct DaycastWeatherPair {
    let today: DaycastWeather
    let tomorrow: DaycastWeather
}

enum DaycastWeatherService {
    static func fetchWeather(for location: CLLocation) async throws -> DaycastWeatherPair {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,precipitation"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]

        let url = components.url!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let forecast = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
        return DaycastWeatherPair(
            today: DaycastWeather(
                condition: conditionName(for: forecast.current.weatherCode),
                temperature: Int(forecast.current.temperature.rounded()),
                high: roundedDailyValue(forecast.daily.temperatureMax, at: 0),
                low: roundedDailyValue(forecast.daily.temperatureMin, at: 0),
                precipitationChance: roundedDailyValue(forecast.daily.precipitationChance, at: 0),
                sunrise: localDate(from: forecast.daily.sunrise[safe: 0]),
                sunset: localDate(from: forecast.daily.sunset[safe: 0])
            ),
            tomorrow: DaycastWeather(
                condition: conditionName(for: forecast.daily.weatherCode[safe: 1] ?? forecast.current.weatherCode),
                temperature: roundedDailyValue(forecast.daily.temperatureMax, at: 1),
                high: roundedDailyValue(forecast.daily.temperatureMax, at: 1),
                low: roundedDailyValue(forecast.daily.temperatureMin, at: 1),
                precipitationChance: roundedDailyValue(forecast.daily.precipitationChance, at: 1),
                sunrise: localDate(from: forecast.daily.sunrise[safe: 1]),
                sunset: localDate(from: forecast.daily.sunset[safe: 1])
            )
        )
    }

    private static func localDate(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return localDateFormatter.date(from: value)
    }

    private static func roundedDailyValue(_ values: [Double], at index: Int) -> Int {
        Int((values[safe: index] ?? 0).rounded())
    }

    private static func conditionName(for code: Int) -> String {
        switch code {
        case 0:
            return "Clear"
        case 1:
            return "Mostly clear"
        case 2:
            return "Partly cloudy"
        case 3:
            return "Cloudy"
        case 45, 48:
            return "Fog"
        case 51, 53, 55:
            return "Drizzle"
        case 56, 57:
            return "Freezing drizzle"
        case 61, 63, 65:
            return "Rain"
        case 66, 67:
            return "Freezing rain"
        case 71, 73, 75, 77:
            return "Snow"
        case 80, 81, 82:
            return "Showers"
        case 85, 86:
            return "Snow showers"
        case 95:
            return "Thunderstorm"
        case 96, 99:
            return "Storm with hail"
        default:
            return "Weather"
        }
    }

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()
}

private struct OpenMeteoForecast: Decodable {
    let current: OpenMeteoCurrent
    let daily: OpenMeteoDaily
}

private struct OpenMeteoCurrent: Decodable {
    let temperature: Double
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case weatherCode = "weather_code"
    }
}

private struct OpenMeteoDaily: Decodable {
    let weatherCode: [Int]
    let temperatureMax: [Double]
    let temperatureMin: [Double]
    let precipitationChance: [Double]
    let sunrise: [String]
    let sunset: [String]

    enum CodingKeys: String, CodingKey {
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case precipitationChance = "precipitation_probability_max"
        case sunrise
        case sunset
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension CLLocation {
    static let daycastFallback = CLLocation(latitude: 53.6833, longitude: -1.4977)
}
