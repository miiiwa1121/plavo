import SwiftUI

/// 撮った1枚を、その画面のまま大きく見る（D42）。
///
/// **画面を移らない。**別のタブや別の画面へ送ると、見終わったあとに
/// カメラへ戻る手間が要る。撮ってすぐ確かめるためのものなので、
/// カメラの上に重ねて、どこを触っても閉じる。
///
/// マイプラントにも同名の役割のものがあるが、あちらは**ギャラリーを
/// 左右に送る**ためのもの。こちらは1枚だけを確かめるためのもので、
/// 送る操作を持たない。
struct PhotoOverlay: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        // 閉じるボタンを探させない。どこを触っても戻れる
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
    }
}
