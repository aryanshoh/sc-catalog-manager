// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CatalogManager",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Порт jsoup — CSS-селекторы и обход DOM, ближайший аналог BeautifulSoup.
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        // Авто-обновление macOS-приложения вне App Store (appcast + EdDSA).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "CatalogManager",
            dependencies: [
                "SwiftSoup",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "CatalogManagerTests",
            dependencies: ["CatalogManager", "SwiftSoup"]
        )
    ]
)
