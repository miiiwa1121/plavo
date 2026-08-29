import SwiftUI

/// マイページ（D13 / D20）。
///
/// 将来はクローズドSNSのプロフィールになるが、今回はアカウントを作らない（D21）。
/// 展示ではリセット操作の置き場としても使う（L-13）。
struct MyPageTab: View {
    @Bindable var model: AppModel
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("これまで") {
                    LabeledContent("育てている植物", value: "1株")
                    LabeledContent("一緒にいる日数", value: "34日")
                    LabeledContent("見送った植物", value: "0株")
                }

                Section {
                    Button("次の来場者のためにリセット", role: .destructive) {
                        showResetConfirm = true
                    }
                } header: {
                    Text("展示")
                } footer: {
                    Text("この回の記録を消して、最初の状態に戻します。")
                }

                if let error = model.loadError {
                    Section("読み込みエラー") {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("マイページ")
            .confirmationDialog(
                "リセットしますか", isPresented: $showResetConfirm, titleVisibility: .visible
            ) {
                Button("リセットする", role: .destructive) { model.reset() }
                Button("やめる", role: .cancel) {}
            }
        }
    }
}
