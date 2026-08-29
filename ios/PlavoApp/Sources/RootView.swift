import SwiftUI

/// アプリの構造。タブ構成（D13）。
///
/// 起動時の既定はカメラ（D2）。カメラがトップ画面であることが、
/// このプロダクトの構造そのものを表す。
///
/// 展示のフロー（説明 → AR → 時系列 → センサー）は説明員と物理配置が担う。
/// アプリの構造とは関係しない。
struct RootView: View {
    @State private var model = AppModel()
    @State private var selection: Int = Self.initialTab

    /// 起動引数でタブを指定できる。動作確認と、展示中に説明員が
    /// 特定のタブから始めたい場面で使う。
    ///   例: -startTab 2
    private static var initialTab: Int {
        guard let raw = UserDefaults.standard.string(forKey: "startTab"),
            let index = Int(raw), (0..<5).contains(index)
        else { return 0 }
        return index
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("カメラ", systemImage: "camera.viewfinder", value: 0) {
                CameraTab(model: model)
            }
            Tab("マイプラント", systemImage: "leaf", value: 1) {
                MyPlantTab(model: model)
            }
            Tab("日記", systemImage: "book", value: 2) {
                DiaryTab(model: model)
            }
            Tab("ルーム", systemImage: "square.grid.2x2", value: 3) {
                RoomTab()
            }
            Tab("マイページ", systemImage: "person", value: 4) {
                MyPageTab(model: model)
            }
        }
        // 起動したら自動でセンサーに繋ぎにいく。
        // 展示で説明員が毎回タップするのは現実的でない。
        // 繋がらなくてもモックで動くため、失敗しても体験は止まらない（F-10）。
        .task { model.startSensor() }
    }
}
