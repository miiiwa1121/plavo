import SwiftUI

/// 画面いっぱいに出す1枚（ギャラリーのメイン・全画面・直近の写真）。
///
/// **ムービー（D58）なら、最初の1コマの上で動画を繰り返し流す。**
///
/// **写真が変わらない限り作り直さない**（`.equatable()` を付けて使う）。
/// これらの画面はページ形式の `TabView` で並べていて、見ている1枚が変わるたびに画面全体が
/// 描き直される。ページの中身まで作り直すと、**1枚送るたびに全ページの写真を開き直す。**
/// プロフィールの100枚余りでは、列をなぞると1コマに数秒かかって固まった。
struct DisplayPhoto: View, @MainActor Equatable {
    /// 写真がまだ無いとき（パラパラの仮の写真は起動後に描く）に出すもの
    enum Placeholder {
        case none
        case quaternary
        case black
    }

    let ref: String
    let model: AppModel
    var contentMode: ContentMode = .fill
    var placeholder: Placeholder = .quaternary

    /// 写真の画像そのものは比べない。**同じ写真なら同じ絵**なので、参照で足りる
    static func == (a: Self, b: Self) -> Bool {
        a.ref == b.ref && a.contentMode == b.contentMode && a.placeholder == b.placeholder
    }

    var body: some View {
        if let image = model.store.displayImage(ref) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                // 最初の1コマと同じ枠に重ねる。読み込むまでの間はその1コマが見えている
                .overlay {
                    if let url = model.store.movieURL(ref) {
                        LoopingMovie(url: url, contentMode: contentMode)
                    }
                }
        } else {
            switch placeholder {
            case .none: Color.clear
            case .quaternary: Rectangle().fill(.quaternary)
            case .black: Color.black
            }
        }
    }
}

extension View {
    /// 見ている1枚の前後を、**裏で**開いておく。
    ///
    /// 送った先の写真をその場で開くと、1枚ごとに引っかかる。列をなぞると1秒に20枚ほど送るので、
    /// 前もって開いておき、送ったときには覚えているものを出すだけにする
    func prefetchingNeighbors(of current: String, in photos: [PlantPhoto], store: PlantStore) -> some View {
        task(id: current) {
            guard let i = photos.firstIndex(where: { $0.ref == current }) else { return }
            for j in [i + 1, i - 1, i + 2, i - 2] where photos.indices.contains(j) {
                if Task.isCancelled { return }
                await store.prepareDisplayImage(photos[j].ref)
            }
        }
    }
}
