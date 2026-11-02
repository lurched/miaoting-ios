import SwiftUI

/// 取自 Android 端 `MainActivity` 的配色常量（背景 #05070A、主色 rgb(0,200,120)、警示 rgb(255,67,78)）。
enum Theme {
    static let background = Color(red: 5 / 255, green: 7 / 255, blue: 10 / 255)
    static let surface = Color(red: 17 / 255, green: 19 / 255, blue: 26 / 255)
    static let surfaceHigh = Color(red: 25 / 255, green: 27 / 255, blue: 34 / 255)
    static let accent = Color(red: 0, green: 200 / 255, blue: 120 / 255)
    static let danger = Color(red: 255 / 255, green: 67 / 255, blue: 78 / 255)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.62)
    static let border = Color(white: 1).opacity(0.08)
}

struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color = Theme.accent
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(fill.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
