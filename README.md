# Pane

A calm, always-on dashboard for Apple TV. It shows the time, the weather and forecast, switches to radar when a storm is close, and adds Home Assistant and GitHub cards, all in Liquid Glass over a background that follows the sky.

Native SwiftUI for tvOS 26 and later. Everything runs in the app, with no server.

## Development

Requirements: macOS with Xcode 27 (including the tvOS simulator runtime) and [Homebrew](https://brew.sh). The Xcode project is generated from `project.yml` with XcodeGen, so it is not checked in.

```sh
scripts/bootstrap.sh   # installs XcodeGen, enables the git hooks, creates local/
scripts/test.sh        # PaneCore tests, then a tvOS Simulator build
scripts/sim.sh run     # builds, installs and launches Pane in the simulator
```

Debug builds read credentials and location from `local/Secrets.local.xcconfig`, which is gitignored. Copy `Config/Secrets.example.xcconfig` to `local/Secrets.local.xcconfig` and fill in the values you have. Put your Apple team ID in `local/Signing.local.xcconfig` as `PANE_TEAM_ID = ...` to sign builds.
