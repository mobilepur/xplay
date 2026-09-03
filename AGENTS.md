# Development Guidelines

## Repository language

- Write documentation, code identifiers, comments, test names, commit messages,
  and pull request content in English.
- Treat user-facing copy as product behavior. Follow the project's localization
  strategy and do not translate it as incidental cleanup.

## Test-driven development

- Work test-first when changing behavior: add or change a failing behavioral test
  before production code.
- Implement only enough code to make the test pass, then refactor if needed.
- Run focused tests during development and the complete test suite before handoff.
- Prefer observable behavior over implementation details in tests.

## Keep changes small

- Build only what the current requirement needs.
- Prefer standard library and platform APIs over new dependencies.
- Introduce abstractions only when current code or tests show a concrete need.
- Keep changes focused, readable, and easy to revise.

## Project files

- Treat `project.yml` as the source of truth for the generated Xcode project.
- Regenerate `XPlay.xcodeproj` with `xcodegen generate` after changing the project
  specification.
- Do not commit `DerivedData`, build products, or Xcode user data.

## Validation

Run the complete test suite before handing off a change:

```sh
xcodebuild test \
  -project XPlay.xcodeproj \
  -scheme XPlay \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/XPlayDerivedData
```

## Git

- Do not force-push unless explicitly requested.
- Commit only coherent changes whose relevant checks pass.
