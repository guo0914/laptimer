import SwiftUI

enum TimerMode: String, Codable, CaseIterable, Hashable {
    case stopwatch
    case countdown

    var title: String {
        switch self {
        case .stopwatch: return "正计时"
        case .countdown: return "倒计时"
        }
    }
}

enum Palette {
    static let background = Color(red: 0.027, green: 0.035, blue: 0.059)
    static let backgroundTop = Color(red: 0.043, green: 0.071, blue: 0.098)

    static let primaryText = Color(red: 0.934, green: 0.949, blue: 0.980)
    static let secondaryText = Color(red: 0.470, green: 0.520, blue: 0.600)
    static let tertiaryText = Color(red: 0.392, green: 0.443, blue: 0.529)
    static let quaternaryText = Color(red: 0.310, green: 0.361, blue: 0.443)

    static let accent = Color(red: 0.369, green: 0.918, blue: 0.831)
    static let accentLight = Color(red: 0.561, green: 0.965, blue: 0.902)
    static let accentInk = Color(red: 0.016, green: 0.129, blue: 0.114)

    static let warn = Color(red: 0.961, green: 0.769, blue: 0.420)
    static let danger = Color(red: 0.941, green: 0.435, blue: 0.435)

    static let surface = Color.white.opacity(0.06)
    static let surfaceRaised = Color.white.opacity(0.09)
    static let surfaceStroke = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.07)

    static let accentGradient = LinearGradient(
        colors: [accentLight, accent],
        startPoint: .top,
        endPoint: .bottom
    )

    static let textGradient = LinearGradient(
        colors: [Color.white, Color(red: 0.72, green: 0.78, blue: 0.86)],
        startPoint: .top,
        endPoint: .bottom
    )
}
