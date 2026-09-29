import XCTest

/// 紹介動画の撮影用の台本（video/README.md）。
///
/// アプリの振る舞いを確かめるテストではない。画面の操作を毎回同じ順と間で流す。
/// 指の跡は `-showTouches YES` でアプリ自身が描く（TouchIndicator）。
///
/// 位置は画面のポイント（左上が原点・iPhone 17 の 402×874）。
final class DemoTourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-startTab", "1", "-showTouches", "YES", "-skipTitle", "YES"]
    }

    func testDemoTour() {
        app.launch()
        pause(1.5)

        // MARK: マイプラント — ひまりを開き、記録 → 育成 → ギャラリー
        tap(app.staticTexts["ひまり"])
        pause(1.6)
        tap(app.buttons["育成"])
        pause(1.2)
        swipe(from: CGPoint(x: 201, y: 640), to: CGPoint(x: 201, y: 330), duration: 0.45)
        pause(1.2)
        tap(app.buttons["ギャラリー"])
        pause(1.8)
        tap(app.navigationBars.buttons.firstMatch)
        pause(0.8)

        // MARK: 日記 — 自分 → 友達（スタンプ）→ みんな（ダブルタップで ❤️）
        tap(app.tabBars.buttons["日記"])
        pause(1.5)
        swipe(from: CGPoint(x: 340, y: 480), to: CGPoint(x: 60, y: 480), duration: 0.3)
        pause(1.2)
        tap(app.buttons["スタンプ"].firstMatch)
        pause(0.9)
        tap(app.buttons["🌸"].firstMatch)
        pause(2.2)
        swipe(from: CGPoint(x: 340, y: 480), to: CGPoint(x: 60, y: 480), duration: 0.3)
        pause(1.2)
        doubleTap(at: CGPoint(x: 201, y: 400))
        pause(2.4)

        // MARK: トーク — わが家のチャットで送る
        tap(app.tabBars.buttons["トーク"])
        pause(1.0)
        tap(app.staticTexts["わが家"])
        pause(1.4)
        let field = app.textFields["メッセージ"].exists ? app.textFields["メッセージ"] : app.textViews.firstMatch
        tap(field)
        pause(0.6)
        field.typeText("今日も元気そう！")
        pause(0.6)
        tap(app.buttons["送信"])
        pause(1.8)
        // チャットの間はタブバーが隠れている。戻ってから次のタブへ
        tap(app.navigationBars.buttons.firstMatch)
        pause(0.8)

        // MARK: プロフィール — 2本指でつまんで、写真の並びを細かくする
        tap(app.tabBars.buttons["プロフィール"])
        pause(1.4)
        // 画面の中央の写真の上でつまむ。画面全体でつまむと、片方の指がタブバーに乗り、
        // 寄せる動きでタブの選択を引っ張ってしまう。
        // 大きくつまむと勢いが付いて10列近くまで進むので、控えめにゆっくりつまむ
        pinch(photo(at: CGPoint(x: 201, y: 470)), scale: 0.6, velocity: -0.8)
        pause(2.0)
    }

    // MARK: - カメラ

    /// デモカメラ（`-demoCamera`・DemoCamera）に映す写真。Mac 上のパスをそのまま渡す。
    /// シミュレータのアプリは Mac のファイルを読める
    private static let cameraPhoto = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../../video/assets/camera-plant.jpg")
        .standardizedFileURL.path

    /// シャッターの帯の高さ。選択中のボタンがいつも中央（x = 201）に来る
    private static let shutterY: CGFloat = 725

    /// カメラ — 植物を迎えて名前をつけ、話しかけてくるのを見て、1枚撮る
    func testCameraTour() {
        app.launchArguments = ["-showTouches", "YES", "-skipTitle", "YES", "-demoCamera", Self.cameraPhoto,
            // 名前をつけて6秒後に水をあげたことにする。「のどが渇いたよ」→「生き返った」
            "-demoWaterAfter", "6"]
        app.launch()
        // 誰も選ばれていないので、映像がぼけている（D52）
        pause(2.0)

        // シャッターを左へ2回滑らせて「迎える」に（撮る → ムービー → 迎える）
        swipe(from: CGPoint(x: 300, y: Self.shutterY), to: CGPoint(x: 150, y: Self.shutterY), duration: 0.25)
        pause(0.7)
        swipe(from: CGPoint(x: 300, y: Self.shutterY), to: CGPoint(x: 150, y: Self.shutterY), duration: 0.25)
        pause(1.0)
        tapAt(CGPoint(x: 201, y: Self.shutterY))
        // 撮った1枚で止まり、植物に枠。「この子でいい？」
        pause(2.2)
        tap(app.buttons["話しかける"])
        // 「はじめまして。名前をつけてくれる？」と名前の入力
        pause(2.4)
        app.textFields["名前をつける"].typeText("まる")
        pause(0.8)
        tap(app.buttons["はじめる"])
        // 挨拶のあと、土の状態に応じたセリフ（乾いている）。6秒後に水が入り、セリフが変わる
        pause(10.0)

        // 撮る。左下の枠に1枚が入る
        tapAt(CGPoint(x: 201, y: Self.shutterY))
        pause(2.0)
        tapAt(CGPoint(x: 48, y: Self.shutterY))
        pause(2.2)
        swipe(from: CGPoint(x: 201, y: 420), to: CGPoint(x: 201, y: 780), duration: 0.3)
        pause(2.5)
    }

    // MARK: - パラパラ

    /// ひまりのパラパラを流す。一生ぶんの写真が1枚ずつめくれる
    func testFlipbookTour() {
        app.launchArguments = [
            "-showTouches", "YES", "-skipTitle", "YES",
            "-startTab", "1", "-openDetail", "YES", "-startDetailPage", "2", "-startGalleryFilter", "3",
        ]
        app.launch()
        pause(1.5)
        // 並びの先頭（いちばん新しい1枚）を開き、再生する。新しい1枚から押すと、いちばん古い1枚からめくる。
        // 先頭の Image は画面外の暗幕なので、位置で押す
        tapAt(CGPoint(x: 67, y: 240))
        pause(1.5)
        tap(app.buttons["パラパラ再生"])
        pause(9.0)
    }

    // MARK: - 操作

    private func tapAt(_ point: CGPoint) {
        coordinate(point).tap()
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "見つからない: \(element)")
        element.tap()
    }

    private func doubleTap(at point: CGPoint) {
        coordinate(point).doubleTap()
    }

    /// 指で引く。速さを決めて引くと、実際の手の動きに近くなる
    private func swipe(from: CGPoint, to: CGPoint, duration: TimeInterval) {
        let distance = hypot(to.x - from.x, to.y - from.y)
        coordinate(from).press(
            forDuration: 0.05,
            thenDragTo: coordinate(to),
            withVelocity: XCUIGestureVelocity(rawValue: distance / duration),
            thenHoldForDuration: 0
        )
    }

    private func pinch(_ element: XCUIElement, scale: CGFloat, velocity: CGFloat) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.pinch(withScale: scale, velocity: velocity)
    }

    /// その位置にある写真。写真の並びの1枚1枚は Image として見える
    private func photo(at point: CGPoint) -> XCUIElement {
        let images = app.scrollViews.images.allElementsBoundByIndex
        return images.first { $0.frame.contains(point) } ?? app.scrollViews.images.firstMatch
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
