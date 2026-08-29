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
                    LabeledContent("状態", value: model.sensor.state.label)
                    LabeledContent("受信数", value: "\(model.sensor.receivedCount)")
                    if let p = model.sensor.lastPayload {
                        LabeledContent(
                            "土の湿り",
                            value: String(format: "%.1f%%  (raw %.0f)", p.soilMoisture.percent, p.soilMoisture.raw))
                        LabeledContent("ガジェット", value: p.gadgetId)
                    }
                    HStack {
                        Text("サーバー")
                        TextField(
                            "http://192.168.x.x:8787",
                            text: Binding(
                                get: { model.sensor.baseURL },
                                set: { model.sensor.baseURL = $0 }))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .font(.callout.monospaced())
                    }
                    Button(model.sensor.state == .idle ? "接続する" : "繋ぎ直す") {
                        model.startSensor()
                    }
                } header: {
                    Text("センサー")
                } footer: {
                    Text("起動時に自動で繋ぎにいきます。繋がらなくてもアプリは動きます。実センサーが無いときは、カメラ画面の長押しで出るモック操作を使ってください。")
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
