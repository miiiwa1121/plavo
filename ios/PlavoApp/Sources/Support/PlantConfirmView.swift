import SwiftUI

/// 撮った1枚。植物の追加で、確認のために画面に留める
struct CapturedPlant: Identifiable {
    let id = UUID()
    let image: UIImage
    /// 見つけた植物の位置。正規化（左上が原点）。見つからなければ nil
    let box: CGRect?
    let plantScore: Float
}

/// 撮った瞬間を止めて、「この植物を見ている」ことを枠で示す。
///
/// カメラを向けただけで勝手に話しかけてくるのとは別に、
/// **迎える相手を自分で確かめてから決める**ための一段。
struct PlantConfirmView: View {
    let captured: CapturedPlant
    let onTalk: () -> Void
    let onRetake: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let size = captured.image.size
                let scale = min(geo.size.width / size.width, geo.size.height / size.height)
                let w = size.width * scale
                let h = size.height * scale
                let ox = (geo.size.width - w) / 2
                let oy = (geo.size.height - h) / 2

                ZStack(alignment: .topLeading) {
                    Image(uiImage: captured.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    if let box = captured.box {
                        // 枠で「この子を見ている」ことを示す
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .frame(width: box.width * w, height: box.height * h)
                            .position(x: ox + box.midX * w, y: oy + box.midY * h)
                            .shadow(color: .black.opacity(0.4), radius: 4)
                    }
                }
            }

            VStack {
                Spacer()
                caption
                buttons
            }
            .padding(.bottom, 34)
        }
    }

    /// 見つからなかったことをエラーにしない（原則3）
    private var caption: some View {
        Text(captured.box == nil ? "うまく見つけられなかったみたい" : "この子でいい？")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.bottom, 20)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            Button("撮り直す") { onRetake() }
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(.white.opacity(0.18), in: Capsule())

            Button {
                onTalk()
            } label: {
                Label("話しかける", systemImage: "bubble.left.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 24).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}
