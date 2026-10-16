// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TradeJournal",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TradeJournalKit",
            targets: ["TradeJournalKit"]
        ),
    ],
    dependencies: [
        // Supabase Swift SDK can be integrated via SPM
        // .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "TradeJournalKit",
            dependencies: [],
            path: "TradeJournal/Sources",
            exclude: ["App/AppMain.swift"]
        ),
        .testTarget(
            name: "TradeJournalKitTests",
            dependencies: ["TradeJournalKit"],
            path: "TradeJournal/Tests"
        ),
    ]
)
