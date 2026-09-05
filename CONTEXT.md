# XPlay

XPlay organizes the Xcode applications a developer wants to build and run together
without keeping Xcode open.

## Language

**XPlay Project**:
A developer-defined application group anchored by one Xcode container and containing
one or more launch configurations.
_Avoid_: Xcode project, saved project

**Xcode Container**:
The `.xcodeproj` or `.xcworkspace` container from which XPlay discovers schemes.
_Avoid_: Project file, workspace when either container type is possible

**Scheme**:
A named Xcode build-and-run definition discovered from an Xcode container.
_Avoid_: Target

**Destination**:
A concrete environment on which a scheme can run, such as the current Mac or an iOS
Simulator.
_Avoid_: Device when the environment may be a simulator or Mac

**Launch Configuration**:
An enabled pairing of one scheme and one selected destination within an XPlay Project.
_Avoid_: Target, selected scheme
