import SwiftUI

// 文字を一文字ずつ時間差で出し入れする。消えるときはぼやけながら direction の向きへ抜け、
// 出るときは反対側から浮かび上がる
@available(macOS 15, *)
struct GlyphRise: TextRenderer, Animatable {
    var progress: Double
    let direction: Double
    let moves: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { line in line.flatMap { run in run } }
        // 文字数が多くても全体の長さが変わらないよう、時間差は全体の 40% に収める
        let stagger = 0.4
        for (index, glyph) in glyphs.enumerated() {
            let start = glyphs.count > 1 ? stagger * Double(index) / Double(glyphs.count - 1) : 0
            let t = min(max((progress - start) / (1 - stagger), 0), 1)
            var copy = context
            copy.opacity = t
            if moves {
                // 出るときは下から、消えるときは上へ。progress が減る向きでは direction を逆にしない
                copy.translateBy(x: 0, y: (1 - t) * 9 * direction)
                copy.addFilter(.blur(radius: (1 - t) * 5))
            }
            copy.draw(glyph)
        }
    }
}
