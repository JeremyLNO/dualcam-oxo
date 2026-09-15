// swift-tools-version:5.9
import PackageDescription

// Vendored copy of OneSignal-XCFramework 5.5.1, trimmed to the OneSignalFramework
// product (In-App Messages and Location are not used).
//
// It is vendored rather than referenced as a remote package because xcodebuild hangs
// forever in -[Xcode3CommandLineBuildTool waitForRemoteSourcePackagesToFinishLoading]
// on GitHub runners as soon as the graph contains any REMOTE package: the checkouts
// finish in seconds, then a KVO condition never flips and the step dies on its timeout.
// The upstream binaryTargets fetched their xcframeworks over the network; here they are
// plain files, so resolution touches nothing outside this directory.
let package = Package(
    name: "OneSignalXCFramework",
    products: [
        .library(name: "OneSignalFramework", targets: ["OneSignalFrameworkWrapper"]),
    ],
    targets: [
        .target(
            name: "OneSignalFrameworkWrapper",
            dependencies: [
                "OneSignalFramework", "OneSignalUser", "OneSignalNotifications",
                "OneSignalLiveActivities", "OneSignalExtension", "OneSignalOutcomes",
                "OneSignalOSCore", "OneSignalCore",
            ],
            path: "OneSignalFrameworkWrapper"
        ),
        .binaryTarget(name: "OneSignalFramework", path: "Frameworks/OneSignalFramework.xcframework"),
        .binaryTarget(name: "OneSignalUser", path: "Frameworks/OneSignalUser.xcframework"),
        .binaryTarget(name: "OneSignalNotifications", path: "Frameworks/OneSignalNotifications.xcframework"),
        .binaryTarget(name: "OneSignalLiveActivities", path: "Frameworks/OneSignalLiveActivities.xcframework"),
        .binaryTarget(name: "OneSignalExtension", path: "Frameworks/OneSignalExtension.xcframework"),
        .binaryTarget(name: "OneSignalOutcomes", path: "Frameworks/OneSignalOutcomes.xcframework"),
        .binaryTarget(name: "OneSignalOSCore", path: "Frameworks/OneSignalOSCore.xcframework"),
        .binaryTarget(name: "OneSignalCore", path: "Frameworks/OneSignalCore.xcframework"),
    ]
)
