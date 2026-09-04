import XCTest
@testable import XPlay

final class XcodeProjectLaunchPlanTests: XCTestCase {
    func testWorkspaceBuildArgumentsUseConfiguredDestinationAndGlobalMacroSetting() {
        let plan = makePlan(acceptsMacros: true)

        XCTAssertEqual(
            plan.buildArguments,
            [
                "-skipMacroValidation",
                "-workspace", "/Projects/Example.xcworkspace",
                "-scheme", "Example-macOS",
                "-configuration", "Debug",
                "-destination", "platform=macOS,id=mac-id",
                "-derivedDataPath", "/tmp/XPlayDerivedData",
                "build",
            ]
        )
    }

    func testSimulatorProductUsesSimulatorBuildDirectory() {
        let plan = makePlan(
            destination: XcodeDestination(
                platform: .iOSSimulator,
                id: "sim-id",
                name: "iPhone 17 Pro"
            )
        )

        XCTAssertEqual(
            plan.builtAppURL.path,
            "/tmp/XPlayDerivedData/Build/Products/Debug-iphonesimulator/Example.app"
        )
    }

    func testCreatesPlanForSelectedConfigurationWithSchemeSpecificPaths() throws {
        let simulator = XcodeDestination(
            platform: .iOSSimulator,
            id: "sim-id",
            name: "iPhone 17 Pro"
        )
        let project = SavedProject(
            url: URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
            kind: .workspace,
            configurations: [
                LaunchConfiguration(
                    scheme: "Example-iOS",
                    isEnabled: true,
                    availableDestinations: [simulator],
                    selectedDestinationID: simulator.id
                ),
            ]
        )

        let configuration = try XCTUnwrap(project.selectedLaunchConfiguration)
        let plan = try XCTUnwrap(XcodeProjectLaunchPlan.make(
            for: project,
            configuration: configuration,
            cacheDirectory: URL(fileURLWithPath: "/Caches/XPlay"),
            acceptsMacros: true
        ))

        XCTAssertEqual(plan.scheme, "Example-iOS")
        XCTAssertEqual(
            plan.derivedDataURL.path,
            "/Caches/XPlay/DerivedData/Example/Example-iOS"
        )
        XCTAssertEqual(
            plan.logURL.path,
            "/Caches/XPlay/Logs/Example-Example-iOS-build.log"
        )
        XCTAssertTrue(plan.acceptsMacros)
    }

    private func makePlan(
        destination: XcodeDestination = XcodeDestination(
            platform: .macOS,
            id: "mac-id",
            name: "My Mac"
        ),
        acceptsMacros: Bool = false
    ) -> XcodeProjectLaunchPlan {
        XcodeProjectLaunchPlan(
            containerURL: URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
            containerKind: .workspace,
            scheme: "Example-macOS",
            destination: destination,
            derivedDataURL: URL(fileURLWithPath: "/tmp/XPlayDerivedData"),
            logURL: URL(fileURLWithPath: "/tmp/Example-build.log"),
            productName: "Example",
            acceptsMacros: acceptsMacros
        )
    }
}
