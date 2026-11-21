# Testing

## Commands

```sh
swift test
./scripts/check-spec.sh
xcodebuild -project Examples/CredflareExample.xcodeproj -scheme CredflareExample -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`swift test` needs Node.js for the contract server. `check-spec.sh` expects `sdk-spec` next to this repository, or its path in `SDK_SPEC_DIR`.

## What is covered

| Area | Tests |
| --- | --- |
| HTTP contract | `ClientTests` against `ContractServer.mjs`, which serves the API responses captured in `sdk-spec/fixtures`: session parsing, document uploads, liveness challenge, gesture, video and selfie uploads with their multipart fields and idempotency keys, facial submission, location submission and location rejections |
| Gesture engine | `EngineTests` replays every trace in `Fixtures/liveness-traces` and checks the face lost reset and provider override rules |
| Liveness logic | `LivenessCaptureTests` drives the challenge with a fake face signal provider: gesture order, position hints, frame capture, timeout, expiry and the Vision sign conventions |
| Location | `LocationTests` covers accuracy, age and mock checks, the fix collector with a fake source, the submission body and place copy built from labels only |
| Rejections | `ClientTests` replays the real backend 422 for every code in `Fixtures/rejections` through the client and checks the applicant copy each one maps to |
| Spec | `SpecTests` parses every icon path and checks copy placeholders and tokens |

The Vision sign test uses a portrait photo from the sibling `website` repository and is skipped when it is missing.

## Local backend

With the local API and the demo server on port 3107 running, this runs a full challenge with fake face signals against the real backend:

```sh
CREDFLARE_DEMO_SESSION_URL=http://localhost:3107/session swift test --filter LiveBackendTests
```

## Devices

The iOS simulator has no camera, so the camera, Vision analysis and video recording have only run in unit tests with injected providers. Before release, run the facial step on a physical iPhone and confirm the gesture prompts complete for each gesture, the video uploads, and the location step on a device with and without precise location.

## Screen previews

Debug builds of the example accept `-screen <name>` and render that SDK screen with fixture data and no network or camera, which is how every screen is reviewed on the simulator in light and dark. The names are listed in `CredflareVerificationView.previewScreens`:

```sh
xcrun simctl launch booted net.credflare.swiftdemo -screen liveness_blink
xcrun simctl io booted screenshot liveness_blink.png
```
