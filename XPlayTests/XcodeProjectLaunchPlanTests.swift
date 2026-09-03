import XCTest
@testable import XPlay

final class XcodeProjectLaunchPlanTests: XCTestCase {
    func testBuildArgumentsSelectConfiguredMacOSScheme() {
        let plan = makePlan()

        XCTAssertEqual(
            plan.buildArguments,
            [
                "-project", "/Projects/Example.xcodeproj",
                "-scheme", "Example-macOS",
                "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", "/tmp/XPlayDerivedData",
                "build",
            ]
        )
    }

    func testBuiltAppPointsToConfiguredDebugProduct() {
        let plan = makePlan()

        XCTAssertEqual(
            plan.builtAppURL.path,
            "/tmp/XPlayDerivedData/Build/Products/Debug/Example.app"
        )
    }

    private func makePlan() -> XcodeProjectLaunchPlan {
        XcodeProjectLaunchPlan(
            projectURL: URL(fileURLWithPath: "/Projects/Example.xcodeproj"),
            scheme: "Example-macOS",
            derivedDataURL: URL(fileURLWithPath: "/tmp/XPlayDerivedData"),
            logURL: URL(fileURLWithPath: "/tmp/Example-build.log"),
            productName: "Example"
        )
    }
}
