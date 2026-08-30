import SwiftUI

/// シャッターの種類。
///
/// 選ばれているものが中央に大きく出て、残りは横に小さく並ぶ。
/// 左右にスライドして切り替える。**今後も種類が増えていく前提**なので、
/// 数に依らず並べられる形にしてある。
enum ShutterMode: String, CaseIterable, Identifiable {
    /// いつもの撮影。今日の日記に写真が入る
    case capture
    /// 植物を迎える。撮った1枚で確かめてから登録する
    case addPlant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .capture: "撮る"
        case .addPlant: "迎える"
        }
    }

    /// 中に描く記号。なければ無地のシャッター
    var symbol: String? {
        switch self {
        case .capture: nil
        case .addPlant: "plus"
        }
    }
}

/// シャッターの並び。
///
/// 選択中は大きく、それ以外は小さく脇に置く。
/// 左右にスライドすると隣へ移る。
struct ShutterBar: View {
    @Binding var mode: ShutterMode
    let onFire: () -> Void
    var disabled = false

    private let bigSize: CGFloat = 72
    private let smallSize: CGFloat = 42
    private let spacing: CGFloat = 20
    /// これ以上滑らせたら隣へ移る
    private let switchThreshold: CGFloat = 34

    private var modes: [ShutterMode] { ShutterMode.allCases }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(modes) { m in
                button(m)
            }
        }
        // 選択中がいつも画面の中央に来るようにずらす
        .offset(x: centeringOffset)
        .animation(.spring(duration: 0.3), value: mode)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    guard let index = modes.firstIndex(of: mode) else { return }
                    if v.translation.width < -switchThreshold, index + 1 < modes.count {
                        mode = modes[index + 1]
                    } else if v.translation.width > switchThreshold, index > 0 {
                        mode = modes[index - 1]
                    }
                }
        )
    }

    private func button(_ m: ShutterMode) -> some View {
        let selected = m == mode
        let size = selected ? bigSize : smallSize
        return Button {
            if selected {
                onFire()
            } else {
                mode = m
            }
        } label: {
            ZStack {
                Circle().fill(.white.opacity(selected ? 0.25 : 0.18))
                Circle().stroke(.white.opacity(selected ? 1 : 0.6), lineWidth: selected ? 3 : 2)
                Circle().fill(.white).padding(selected ? 7 : 5)
                if let symbol = m.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                }
            }
            .frame(width: size, height: size)
        }
        .disabled(disabled && selected)
        .opacity(disabled && selected ? 0.5 : 1)
    }

    /// 選択中のボタンの中心を、並び全体の中心に合わせるためのずらし量
    private var centeringOffset: CGFloat {
        guard let index = modes.firstIndex(of: mode) else { return 0 }
        let widths = modes.enumerated().map { $0.element == mode ? bigSize : smallSize }
        let total = widths.reduce(0, +) + spacing * CGFloat(modes.count - 1)
        let before = widths.prefix(index).reduce(0, +) + spacing * CGFloat(index)
        let selectedCenter = before + widths[index] / 2
        return total / 2 - selectedCenter
    }
}
