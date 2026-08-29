import SwiftUI

/// ルーム（D16）。正方形の3D空間に、育てた植物や集めたものを並べる。
///
/// RealityKit で実装する（D16-a）が、今回の実装スコープからは外している（D21）。
/// 3Dアセットの調達がボトルネックになるため（L-7）。枠だけ残す。
struct RoomTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("準備中")
                    .font(.headline)
                Text("育てた植物や集めたものを並べる\n自分だけの部屋になります")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("ルーム")
        }
    }
}
