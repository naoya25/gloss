import AppKit
import SwiftUI

// Slack などに貼る今日のレポートの画像。画面の Report をそのまま明るい色で描く。
// 貼り先の地の色が分からないので、暗い表示のときも明るい色に決め打ちにする
enum ReportShareCard {
    // PNG と TIFF の両方を入れて、どの貼り先でも受け取れるようにする
    @MainActor
    static func copy(activity: ActivityStore, words: WordsStore) -> Bool {
        let card = ReportOverview(isSnapshot: true)
            .environment(activity)
            .environment(words)
            .frame(width: 860, alignment: .leading)
            .padding(32)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([item])
    }
}
