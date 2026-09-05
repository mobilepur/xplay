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
        XCTAssertEqual(plan.derivedDataURL.deletingLastPathComponent().path, "/Caches/XPlay/DerivedData")
        XCTAssertEqual(plan.logURL.deletingLastPathComponent().path, "/Caches/XPlay/Logs")
        XCTAssertTrue(plan.acceptsMacros)
    }

    func testStoragePathsAreStableAndIsolateContainersAndSchemes() throws {
        let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
        func plan(path: String, scheme: String = "Example") throws -> XcodeProjectLaunchPlan {
            let configuration = LaunchConfiguration(
                scheme: scheme, isEnabled: true,
                availableDestinations: [mac], selectedDestinationID: mac.id
            )
            return try XCTUnwrap(XcodeProjectLaunchPlan.make(
                for: SavedProject(url: URL(fileURLWithPath: path), kind: .project),
                configuration: configuration,
                cacheDirectory: URL(fileURLWithPath: "/Caches/XPlay"), acceptsMacros: false
            ))
        }
        let main = try plan(path: "/repos/main/Example.xcodeproj")
        let other = try plan(path: "/repos/feature/Example.xcodeproj")
        XCTAssertNotEqual(main.derivedDataURL, other.derivedDataURL)
        XCTAssertNotEqual(main.logURL, other.logURL)
        XCTAssertEqual(main, try plan(path: "/repos/main/Example.xcodeproj"))
        XCTAssertEqual(main, try plan(path: "/repos/main/../main/Example.xcodeproj"))
        let slash = try plan(path: "/repos/main/Example.xcodeproj", scheme: "App/iOS")
        let colon = try plan(path: "/repos/main/Example.xcodeproj", scheme: "App:iOS")
        XCTAssertNotEqual(slash.derivedDataURL, colon.derivedDataURL)
        XCTAssertNotEqual(slash.logURL, colon.logURL)
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
