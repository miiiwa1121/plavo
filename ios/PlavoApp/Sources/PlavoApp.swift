import SwiftUI

@main
struct PlavoApp: App {
    /// アプリ全体の状態。**ここで1回だけ作る。**
    ///
    /// `RootView` の `@State` に置いていた頃は、`RootView` が作り直されるたびに
    /// 初期値の `AppModel()` も評価され、作っては捨てていた（`@State` が残すのは最初の1つだけ）。
    /// パラパラの仮写真を起動後に裏で描くようにしてから、捨てた側の書き換えが画面の作り直しを呼び、
    /// それがまた `AppModel` を作る、という輪になった。**何もしていなくても CPU を1コア使い切っていた**
    /// （1秒に約10回、育成の記録 0.8MB を読み直していた）
    ///
    /// **作るのは画面が出てから。**`@State` の初期値にすると、アプリが立ち上がる前に
    /// 仮写真を描く（UIKit を触る）ことになり、アクセント色（D55）が効かず全体が青に戻った
    @State private var model: AppModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else {
                    Color.clear.onAppear { model = AppModel() }
                }
            }
            // 展示中に画面が消えると来場者の体験が途切れる
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
