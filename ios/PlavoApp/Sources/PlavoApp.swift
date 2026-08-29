import SwiftUI

@main
struct PlavoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // 展示中に画面が消えると来場者の体験が途切れる
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
