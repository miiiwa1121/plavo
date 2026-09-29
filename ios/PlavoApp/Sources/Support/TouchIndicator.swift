import UIKit

/// 指の位置に丸を出す。**紹介動画の撮影用**（video/README.md）。起動引数 `-showTouches YES` のときだけ効く。
///
/// シミュレータの録画には指が映らない。録画の外で指の跡を描き足そうとしたが、
/// 録画の時刻が壁時計から少しずつずれ（80秒で約2秒）、押した瞬間と合わなかった。
/// アプリの側で描けば、指の跡も画面と同じ録画に入る。
///
/// 画面の上に触れない窓を1枚重ね、そこへ描く。指を拾うのは元の窓に付けた認識で、
/// ほかの認識の邪魔をしない（触れたものを取り上げず、失敗して終わる）
@MainActor
enum TouchIndicator {
    private static var overlay: UIWindow?

    static func installIfRequested() {
        guard UserDefaults.standard.bool(forKey: "showTouches"), overlay == nil else { return }
        // 窓ができるのは最初の画面が出たあと
        DispatchQueue.main.async(execute: install)
    }

    private static func install() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: install)
            return
        }
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.isHidden = false
        self.overlay = overlay
        window.addGestureRecognizer(TouchObserver(canvas: overlay))
    }
}

/// 指を見ているだけの認識。何も認識せず、指が全部離れたら失敗して次に備える
private final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let canvas: UIView
    private var dots: [ObjectIdentifier: UIView] = [:]

    init(canvas: UIView) {
        self.canvas = canvas
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let dot = Self.makeDot()
            dot.center = touch.location(in: nil)
            dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            dot.alpha = 0
            canvas.addSubview(dot)
            dots[ObjectIdentifier(touch)] = dot
            UIView.animate(withDuration: 0.12) {
                dot.transform = .identity
                dot.alpha = 1
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            dots[ObjectIdentifier(touch)]?.center = touch.location(in: nil)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        lift(touches, event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        lift(touches, event: event)
    }

    private func lift(_ touches: Set<UITouch>, event: UIEvent) {
        for touch in touches {
            guard let dot = dots.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            UIView.animate(withDuration: 0.3) {
                dot.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                dot.alpha = 0
            } completion: { _ in
                dot.removeFromSuperview()
            }
        }
        if dots.isEmpty { state = .failed }
    }

    /// 白い画面にも写真の上にも見えるよう、半透明の灰に白の縁
    private static func makeDot() -> UIView {
        let size: CGFloat = 46
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        dot.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        dot.layer.cornerRadius = size / 2
        dot.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        dot.layer.borderWidth = 2.5
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.18
        dot.layer.shadowRadius = 6
        dot.layer.shadowOffset = .zero
        return dot
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
