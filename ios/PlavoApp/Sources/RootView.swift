import PlavoCore
import SwiftUI

/// 展示の全体。4セクションを一本道でたどる（D33）。
///
/// タブではなくフローにしているのは、来場者が順番を崩すと何を見ているのか
/// 分からなくなるため。製品版のタブ構成（D13）とは別物として扱う。
struct RootView: View {
    @State private var session = ExhibitionSession()
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            content
                .transition(.opacity)

            VStack {
                header
                Spacer()
                footer
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.section)
        .overlay(alignment: .topTrailing) { staffControl }
        .confirmationDialog(
            "最初から始めますか",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("リセットする", role: .destructive) { session.reset() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("次の来場者のために、この回の記録を消します")
        }
    }

    // MARK: - 中身

    @ViewBuilder
    private var content: some View {
        if let error = session.loadError {
            LoadFailureView(message: error)
        } else {
            switch session.section {
            case .intro: IntroView()
            case .livePlant: LivePlantView(session: session)
            case .timeline: TimelineView(session: session)
            case .sensor: SensorView(session: session)
            }
        }
    }

    // MARK: - 進行の枠

    private var header: some View {
        VStack(spacing: 4) {
            Text(session.section.title)
                .font(.headline)
            Text(session.section.value)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressDots(
                total: ExhibitionSession.Section.allCases.count,
                current: session.section.rawValue
            )
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var footer: some View {
        HStack {
            Button {
                session.back()
            } label: {
                Label("もどる", systemImage: "chevron.left")
            }
            .disabled(!session.canGoBack)

            Spacer()

            Button {
                session.advance()
            } label: {
                Label("つぎへ", systemImage: "chevron.right")
            }
            .disabled(!session.canAdvance)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// 説明員用のリセット操作（L-13）。
    /// 体験中に誤って押されないよう、目立たない位置で長押しにしている。
    private var staffControl: some View {
        Color.clear
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.0) {
                showResetConfirm = true
            }
            .accessibilityHidden(true)
    }
}

private struct ProgressDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct LoadFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("セリフを読み込めませんでした")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
