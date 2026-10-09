import SwiftUI

// 裏を開いているカードは、縁と下地にほんのりアクセント色を差して、どれを開いているか分かるようにする
struct CardSurface<Content: View>: View {
    var isOpen = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(isOpen ? 0.08 : 0)))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? AnyShapeStyle(Color.accentColor.opacity(0.5)) : AnyShapeStyle(.separator)))
    }
}
