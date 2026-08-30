import SwiftUI

/// アイコンにする範囲を決める。
///
/// 写真をそのまま丸く切ると、たいてい狙った場所が入らない。
/// 拡大と移動で位置を合わせてから確定する。
struct AvatarCropView: View {
    let image: UIImage
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    /// 実際に描かれている円の直径。切り抜きの計算に使う
    @State private var diameter: CGFloat = 0

    /// 切り抜く円の直径が画面幅に占める割合
    private let cropRatio: CGFloat = 0.78
    private let maxZoom: CGFloat = 5

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height) * cropRatio

                ZStack {
                    Color.black.ignoresSafeArea()

                    canvas(diameter: d, in: geo.size)

                    // 円の外を暗くして、切り抜かれる範囲を示す
                    mask(diameter: d)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(diameter: d))
                .simultaneousGesture(magnifyGesture(diameter: d))
                // 確定時に画面の実寸が要る。推測すると切り抜き位置がずれる
                .onAppear { diameter = d }
                .onChange(of: d) { _, new in diameter = new }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("アイコンにする範囲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") { commit() }
                }
            }
        }
    }

    // MARK: - 表示

    private func canvas(diameter: CGFloat, in size: CGSize) -> some View {
        let base = baseScale(diameter: diameter)
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: image.size.width * base, height: image.size.height * base)
            .scaleEffect(zoom)
            .offset(offset)
            .frame(width: size.width, height: size.height)
    }

    private func mask(diameter: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .mask {
                    Rectangle()
                        .overlay {
                            Circle().frame(width: diameter, height: diameter).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: diameter, height: diameter)
        }
    }

    // MARK: - 操作

    private func dragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { v in
                offset = CGSize(
                    width: committedOffset.width + v.translation.width,
                    height: committedOffset.height + v.translation.height)
            }
            .onEnded { _ in
                offset = clamped(offset, diameter: diameter)
                committedOffset = offset
            }
    }

    private func magnifyGesture(diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                zoom = min(maxZoom, max(1, committedZoom * v.magnification))
            }
            .onEnded { _ in
                committedZoom = zoom
                offset = clamped(offset, diameter: diameter)
                committedOffset = offset
            }
    }

    /// 円の外に余白が出ないよう、移動量を抑える
    private func clamped(_ value: CGSize, diameter: CGFloat) -> CGSize {
        let k = baseScale(diameter: diameter) * zoom
        let limitX = max(0, (image.size.width * k - diameter) / 2)
        let limitY = max(0, (image.size.height * k - diameter) / 2)
        return CGSize(
            width: min(limitX, max(-limitX, value.width)),
            height: min(limitY, max(-limitY, value.height)))
    }

    /// 円をちょうど埋める倍率
    private func baseScale(diameter: CGFloat) -> CGFloat {
        max(diameter / image.size.width, diameter / image.size.height)
    }

    // MARK: - 切り抜き

    /// 画面上の見え方を、元画像の座標に戻して切り抜く。
    ///
    /// 画面を描画してから縮小すると解像度を落とすため、**元画像から直接切る。**
    ///
    /// 円の中心は常に画面の中心にある。画像の中心は、そこから offset だけ
    /// ずれている。よって円の中心は、画像座標では中心から -offset/k の位置になる。
    private func commit() {
        guard diameter > 0 else {
            dismiss()
            return
        }
        let k = baseScale(diameter: diameter) * zoom
        let side = diameter / k
        let x = image.size.width / 2 - offset.width / k - side / 2
        let y = image.size.height / 2 - offset.height / k - side / 2

        guard let cropped = crop(rect: CGRect(x: x, y: y, width: side, height: side)) else {
            dismiss()
            return
        }
        if let data = cropped.jpegData(compressionQuality: 0.9) { onDone(data) }
        dismiss()
    }

    private func crop(rect: CGRect) -> UIImage? {
        guard let cg = normalized().cgImage else { return nil }
        let scale = CGFloat(cg.width) / image.size.width
        let px = CGRect(
            x: rect.origin.x * scale, y: rect.origin.y * scale,
            width: rect.width * scale, height: rect.height * scale
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let cut = cg.cropping(to: px.intersection(bounds)) else { return nil }
        return UIImage(cgImage: cut)
    }

    /// 向きの情報を持ったままだと切り抜きの座標がずれるので、起こしておく
    private func normalized() -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }
}
