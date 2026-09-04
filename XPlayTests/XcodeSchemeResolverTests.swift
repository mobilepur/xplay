import Foundation
import XCTest
@testable import XPlay

final class XcodeSchemeResolverTests: XCTestCase {
    func testDiscoversWorkspaceSchemesFromXcodebuildJSON() throws {
        var receivedArguments: [String] = []
        let resolver = XcodeSchemeResolver { arguments in
            receivedArguments = arguments
            return Data(
                """
                {
                  "workspace": {
                    "name": "Example",
                    "schemes": ["Example", "ExampleTests"]
                  }
                }
                """.utf8
            )
        }

        let schemes = try resolver.schemes(
            for: URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
            kind: .workspace
        )

        XCTAssertEqual(
            receivedArguments,
            ["-list", "-json", "-workspace", "/Projects/Example.xcworkspace"]
        )
        XCTAssertEqual(schemes, ["Example", "ExampleTests"])
    }

    func testDiscoversConcreteMacAndIOSSimulatorDestinations() throws {
        var receivedArguments: [String] = []
        let resolver = XcodeSchemeResolver { arguments in
            receivedArguments = arguments
            return Data(
                """
                Available destinations for the "Example" scheme:
                    { platform:macOS, arch:arm64, id:mac-id, name:My Mac }
                    { platform:macOS, arch:x86_64, id:mac-id, name:My Mac }
                    { platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:mac-id, name:My Mac }
                    { platform:iOS, arch:arm64, id:phone-id, name:Bastian's iPhone }
                    { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
                    { platform:iOS Simulator, arch:arm64, id:sim-id, OS:26.0, name:iPhone 17 Pro }
                    { platform:iOS Simulator, arch:arm64, id:sim-2, OS:18.5, name:iPad mini (A17 Pro) }
                """.utf8
            )
        }

        let destinations = try resolver.destinations(
            for: URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
            kind: .workspace,
            scheme: "Example"
        )

        XCTAssertEqual(
            receivedArguments,
            [
                "-showdestinations",
                "-workspace", "/Projects/Example.xcworkspace",
                "-scheme", "Example",
            ]
        )
        XCTAssertEqual(
            destinations,
            [
                XcodeDestination(platform: .macOS, id: "mac-id", name: "My Mac"),
                XcodeDestination(
                    platform: .iOSSimulator,
                    id: "sim-id",
                    name: "iPhone 17 Pro",
                    osVersion: "26.0"
                ),
                XcodeDestination(
                    platform: .iOSSimulator,
                    id: "sim-2",
                    name: "iPad mini (A17 Pro)",
                    osVersion: "18.5"
                ),
            ]
        )
    }

    func testProcessRunnerDrainsLargeOutputAndDiagnosticsConcurrently() throws {
        let script = """
        i=0
        while [ $i -lt 10000 ]; do
          echo "standard output payload"
          echo "diagnostic payload" >&2
          i=$((i + 1))
        done
        """

        let result = try XcodeSchemeResolver.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.count, 65_536)
        XCTAssertGreaterThan(result.diagnostic.count, 65_536)
    }
}
