import SwiftUI

struct CardLine: View {
    let label: String
    let text: String
    let translation: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let translation, !translation.isEmpty {
                    Text(translation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
