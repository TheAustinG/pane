import SwiftUI

/// Pane tokens in tvOS points on the 1920x1080 canvas. The tvOS HIG puts the legibility floor at
/// 23 pt, so no text role goes below 24.
enum Theme {
    enum Ink {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.80)
        static let tertiary = Color.white.opacity(0.72)
        static let rule = Color.white.opacity(0.20)
        static let well = Color.white.opacity(0.14)
        static let faint = Color.white.opacity(0.10)
    }

    enum Signal {
        static let rain = Color(hex: 0xA9DBFF)
        static let sun = Color(hex: 0xFFE6AA)
        static let nudge = Color(hex: 0xFFD27F)
        static let nudgeInk = Color(hex: 0xFFE2A8)
        static let nudgeFill = Color(hex: 0xFFBE5A).opacity(0.18)
        static let nudgeStroke = Color(hex: 0xFFCD78).opacity(0.40)
        static let warning = Color(hex: 0xFFA898)
        static let warningFill = Color(hex: 0xFF5A46).opacity(0.24)
        static let warningStroke = Color(hex: 0xFF8C78).opacity(0.55)
    }

    enum Glass {
        static let cornerRadius: CGFloat = 40
        static let chipRadius: CGFloat = 20
        static let shade = Color(hex: 0x0E1024)
        static let focusScale: CGFloat = 1.04
        static let pressedScale: CGFloat = 0.98
        static let focusSheen = Color.white.opacity(0.16)
        static let focusRim = Color.white.opacity(0.75)
        static let rimWidth: CGFloat = 2
        static let liftShadow = Color(hex: 0x080818).opacity(0.45)
        static let liftRadius: CGFloat = 28
        static let liftOffset: CGFloat = 26
        static let textShadow = Color.black.opacity(0.22)
    }

    enum Size {
        static let clock: CGFloat = 300
        static let heroTemp: CGFloat = 132
        static let meridiem: CGFloat = 64
        static let date: CGFloat = 52
        static let title: CGFloat = 40
        static let headline: CGFloat = 36
        static let metric: CGFloat = 32
        static let body: CGFloat = 30
        static let callout: CGFloat = 28
        static let subhead: CGFloat = 26
        static let caption: CGFloat = 24
    }

    enum Typeface {
        static let clock = Font.system(size: Size.clock, weight: .thin)
        static let meridiem = Font.system(size: Size.meridiem, weight: .light)
        static let date = Font.system(size: Size.date, weight: .regular)
        static let screenTitle = Font.system(size: Size.date, weight: .semibold)
        static let heroTemp = Font.system(size: Size.heroTemp, weight: .thin)
        static let title = Font.system(size: Size.title, weight: .medium)
        static let headline = Font.system(size: Size.headline, weight: .semibold)
        static let metric = Font.system(size: Size.metric, weight: .medium).monospacedDigit()
        static let body = Font.system(size: Size.body, weight: .regular)
        static let bodyStrong = Font.system(size: Size.body, weight: .medium)
        static let callout = Font.system(size: Size.callout, weight: .regular)
        static let subhead = Font.system(size: Size.subhead, weight: .regular)
        static let subheadStrong = Font.system(size: Size.subhead, weight: .semibold)
        static let caption = Font.system(size: Size.caption, weight: .regular)
        static let label = Font.system(size: Size.caption, weight: .semibold)
        static let labelTracking: CGFloat = 1.9
    }

    enum Space {
        static let xxs: CGFloat = 6
        static let xs: CGFloat = 10
        static let s: CGFloat = 14
        static let m: CGFloat = 18
        static let l: CGFloat = 28
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    enum Layout {
        static let canvas = CGSize(width: 1920, height: 1080)
        static let marginVertical: CGFloat = 72
        static let marginHorizontal: CGFloat = 96
        static let gutter: CGFloat = 32
        static let topRowHeight: CGFloat = 464
        static let bottomRowHeight: CGFloat = 440
        static let weatherWidth: CGFloat = 600
        static let forecastWidth: CGFloat = 700
        static let sideCardWidth: CGFloat = 482
        static let paneInset = EdgeInsets(top: 30, leading: 40, bottom: 30, trailing: 40)
        static let stormColumnWidth: CGFloat = 600
        static let stormStripHeight: CGFloat = 252
        static let iconWell: CGFloat = 52
    }

    enum Motion {
        static let focus = Animation.spring(response: 0.35, dampingFraction: 0.82)
        static let state = Animation.easeOut(duration: 0.2)
        static let takeover = Animation.easeInOut(duration: 0.6)
        static let nightDim = Animation.easeInOut(duration: 3)
        static let sceneBlendSeconds: Double = 90
        static let driftPeriods: [Double] = [34, 41, 47, 53]
    }

    enum Dim {
        static let night: Double = 0.30
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
