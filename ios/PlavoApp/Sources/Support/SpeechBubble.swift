import SwiftUI

/// セリフの吹き出し。
///
/// 漫画の記法をそのまま使う（D2）。会話は尖った吹き出し、夢は雲形。
/// 見ただけで「喋っている / 夢を見ている」が伝わるので、説明が要らない。
///
/// D5 により声は当てない。文字だけで成立させる。
struct SpeechBubble: View {
    let text: String
    var tailAlignment: HorizontalAlignment = .center

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background {
                BubbleShape(tailAlignment: tailAlignment)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            }
            .padding(.bottom, 14)  // しっぽの分
    }
}

/// 尖ったしっぽを持つ吹き出しの形
private struct BubbleShape: Shape {
    let tailAlignment: HorizontalAlignment

    func path(in rect: CGRect) -> Path {
        let tailHeight: CGFloat = 14
        let tailWidth: CGFloat = 20
        let body = CGRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        let radius = min(24, body.height / 2)

        var path = Path(roundedRect: body, cornerRadius: radius)

        let tailCenterX: CGFloat =
            switch tailAlignment {
            case .leading: body.minX + body.width * 0.25
            case .trailing: body.minX + body.width * 0.75
            default: body.midX
            }

        path.move(to: CGPoint(x: tailCenterX - tailWidth / 2, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: tailCenterX - tailWidth / 6, y: body.maxY + tailHeight))
        path.addLine(to: CGPoint(x: tailCenterX + tailWidth / 2, y: body.maxY - 1))
        path.closeSubpath()

        return path
    }
}

#Preview {
    VStack(spacing: 40) {
        SpeechBubble(text: "のどが渇いたよ")
        SpeechBubble(text: "ああ、生き返った")
        SpeechBubble(text: "……")
    }
    .padding()
    .background(Color.green.opacity(0.2))
}
