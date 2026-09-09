# Codex Quota Implementation Plan

> Execute inline using executing-plans; the user has already approved implementation.

**Goal:** Deliver a native macOS quota panel that attaches to Codex and follows its visibility.

**Architecture:** Swift package with a dependency-free QuotaCore library and AppKit/SwiftUI executable. Read quota through a persistent Codex app-server subprocess; track public window metadata independently.

**Tech Stack:** Swift 5 language mode, macOS 13+, SwiftUI, AppKit, ServiceManagement, XCTest.

**Spec:** docs/superpowers/specs/2026-09-07-codex-quota-design.md

## Global Constraints

- Only com.openai.codex windows are attachment targets.
- No API keys, no token storage, no AI polling tasks, no third-party dependencies.
- Poll every 60 seconds by default; configurable 30/120/300.
- Always-on-top and follow visibility are distinct modes.
- Use a separate new project directory; do not modify existing user projects.

## Task 1: Quota and window policies

Files: Package.swift, Sources/QuotaCore/Quota.swift, Sources/QuotaCore/Attachment.swift, Tests/QuotaCoreTests/CoreTests.swift.

Interfaces: QuotaSnapshot.decode(Data), QuotaWindow.remainingPercent, Attachment.snap(panel:target:threshold:), Attachment.frame(target:size:screen:), DisplayMode.shouldShow(targetVisible:targetActive:).

- [x] Write table-driven tests with literal quota fixtures and hand-computed rectangles, run `swift test` and observe failure.
- [x] Implement decoding that prefers rateLimitsByLimitId, clamps percentages, preserves absent windows, and rejects empty snapshots.
- [x] Implement four-edge snapping, screen fitting and three visibility modes; rerun `swift test`.

## Task 2: Native app and live data

Files: Sources/CodexQuota/{main,QuotaClient,WindowTracker,AppModel,QuotaView,AppDelegate}.swift.

- [x] QuotaClient sends initialize then initialized then account/rateLimits/read; timeout after 20s, one pending read, terminate on shutdown, retry with backoff.
- [x] WindowTracker matches Codex PID and public normal-window IDs, converts CG to AppKit coordinates, tracks selected ID without hopping windows.
- [x] NSPanel follows tracker, snaps on drag end, stores frame and mode, exposes menu bar controls.
- [x] SwiftUI card shows real quota/reset status, fold, mode picker, refresh controls and login switch.
- [x] Run `swift build`; run executable `--check-quota` against actual local Codex; render light/dark/compact previews and inspect.

## Task 3: Packaging and verification

Files: Resources/Info.plist, scripts/build.sh, README.md.

- [x] Build release, create .app and icon, sign locally, install to ~/Applications.
- [x] Run `swift test`, `codesign --verify`, launch app; verify live quota and tracker state using read-only diagnostics.
- [x] Exercise real movement/minimize/hide/restore when OS permissions allow, preserving original window state.
- [x] Document launch settings, modes, update behavior and any unverified OS scenarios; report artifact paths.

## Verification outcome

2026-09-07: 13 tests pass; native quota probe succeeds; release build and signature verify. Real Codex hide/unhide checks pass for follow and always-on-top modes. All three rendered themes/layouts visually inspected. Mouse drag, minimize animation, Spaces/fullscreen and logout/login were not automatically exercised; see README. Independent review findings on resize screen bounds and inside-edge snapping were reproduced in failing tests and fixed.
