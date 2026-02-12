import SwiftUI
import NukeUI

struct MessagePublicationCardView: View {

    let attachment: MessagePublicationAttachment
    let isOutgoing: Bool

    // MARK: - Layout Constants

    private enum Layout {
        static let photoSize: CGFloat = 34
        static let photoCornerRadius: CGFloat = 4
        static let accentLineWidth: CGFloat = 2
        static let accentLineCornerRadius: CGFloat = 1
        static let cardCornerRadius: CGFloat = 14
        static let cardPadding: CGFloat = 6
        static let textLineLimit: Int = 2
        static let fontSize: CGFloat = 12
    }

    // MARK: - Colors

    private var cardBackground: Color {
        isOutgoing
            ? Color.white.opacity(0.12)
            : Color(red: 0.94, green: 0.95, blue: 0.96)
    }

    private var accentLineColor: Color {
        isOutgoing
            ? Color.white.opacity(0.5)
            : Color(red: 0.44, green: 0.31, blue: 0.98)
    }

    private var textColor: Color {
        isOutgoing
            ? Color.white.opacity(0.85)
            : Color(red: 0.22, green: 0.24, blue: 0.27)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: Layout.accentLineCornerRadius)
                .fill(accentLineColor)
                .frame(width: Layout.accentLineWidth)
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 6) {
                photoView

                Text(attachment.text)
                    .font(.system(size: Layout.fontSize))
                    .foregroundColor(textColor)
                    .lineLimit(Layout.textLineLimit)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 6)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(cardBackground)
        )
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoView: some View {
        if let photoURL = attachment.photoURL {
            LazyImage(url: photoURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    photoPlaceholder
                }
            }
            .processors([.resize(width: Layout.photoSize * UIScreen.main.scale)])
            .frame(width: Layout.photoSize, height: Layout.photoSize)
            .clipShape(RoundedRectangle(cornerRadius: Layout.photoCornerRadius))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: Layout.photoCornerRadius)
            .fill(
                isOutgoing
                    ? Color.white.opacity(0.1)
                    : Color(red: 0.88, green: 0.89, blue: 0.90)
            )
    }
}
