import SwiftUI

/// アプリの構造。タブ構成（D13）。
///
/// 起動時の既定はカメラ（D2）。カメラがトップ画面であることが、
/// このプロダクトの構造そのものを表す。
///
/// 展示のフロー（説明 → AR → 時系列 → センサー）は説明員と物理配置が担う。
/// アプリの構造とは関係しない。
struct RootView: View {
    /// 持ち主は `PlavoApp`。ここで作らない（作り直されるたびに作ってしまう）
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = Self.initialTab

    /// 起動引数でタブを指定できる。動作確認と、展示中に説明員が
    /// 特定のタブから始めたい場面で使う。
    ///   例: -startTab 2
    private static var initialTab: AppTab {
        UserDefaults.standard.string(forKey: "startTab")
            .flatMap(Int.init)
            .flatMap(AppTab.init(rawValue:))
            ?? .camera
    }

    var body: some View {
        TabView(selection: $selection) {
            // タブバーはアイコンだけにする。名前は読み上げのために残す
            Tab(value: AppTab.camera) {
                CameraTab(model: model)
            } label: {
                Label("カメラ", systemImage: "camera.viewfinder").labelStyle(.iconOnly)
            }
            Tab(value: AppTab.myPlant) {
                MyPlantTab(model: model)
            } label: {
                Label("マイプラント", systemImage: "leaf").labelStyle(.iconOnly)
            }
            Tab(value: AppTab.diary) {
                DiaryTab(model: model)
            } label: {
                Label("日記", systemImage: "book").labelStyle(.iconOnly)
            }
            Tab(value: AppTab.talk) {
                TalkTab()
            } label: {
                Label("トーク", systemImage: "bubble.left.and.bubble.right").labelStyle(.iconOnly)
            }
            Tab(value: AppTab.profile) {
                MyPageTab(model: model)
            } label: {
                Label("プロフィール", systemImage: "person").labelStyle(.iconOnly)
            }
        }
        // 起動したら自動でセンサーに繋ぎにいく。
        // 展示で説明員が毎回タップするのは現実的でない。
        // 繋がらなくてもモックで動くため、失敗しても体験は止まらない（F-10）。
        .task { model.startSensor() }
        // 日が変われば日記のページが自動で増える。
        // 起動時と、前面に戻ったときに確かめる。
        .onAppear { model.store.ensureTodayPage() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.store.ensureTodayPage() }
        }
    }
}

/// タブの並び。**番号は起動引数 `-startTab` の値**（ios/README.md の表）。
/// 並びを変えるときは README の表も直す
enum AppTab: Int, CaseIterable {
    case camera
    case myPlant
    case diary
    case talk
    case profile
}
