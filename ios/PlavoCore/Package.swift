// swift-tools-version: 6.0
import PackageDescription

// plavo のドメイン層。
// UI にも AR にも永続化にも依存しない純粋なロジックだけを置く。
// macOS でもビルドできるようにしてあるのは、実機なしに swift test で検証するため。
let package = Package(
    name: "PlavoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlavoCore", targets: ["PlavoCore"])
    ],
    targets: [
        .target(name: "PlavoCore"),
        .testTarget(name: "PlavoCoreTests", dependencies: ["PlavoCore"]),
    ]
)
