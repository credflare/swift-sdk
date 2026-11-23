# Credflare Swift SDK

Native iOS collection of documents, liveness challenge evidence and location, with an async applicant session client. Development SDK for iOS 16 and newer, distributed as a Swift package. Requires scoped-session backend support.

```swift
import CredflareSDK

CredflareVerificationView(sessionProvider: {
    try await authenticatedBackend.createApplicantSession()
}, autoStart: true) { result in
    handleCollectionResult(result)
}
```

The host backend creates or resumes the correct case and returns a temporary `SessionDescriptor`. Server client credentials stay on that backend. Closing the view preserves the case. Results distinguish collected documents, cancellation and checks requiring the host application. A receipt is separate from a verification decision.

Each document follows the backend's capture rule: saved files, camera photos, either source, or both sources. The view guides requested sides, preview, replacement and review. It refreshes requirements after collection, preserving grouped document choices. Credflare branding stays in a small footer; the verifier's name appears in the header.

Camera source is client-reported. The liveness challenge records a server chosen sequence of movements for a reviewer; it does not prove a live person and does not detect deepfakes. Questions and email or phone codes run in the view; question types it does not support return to the host app. Unsent evidence stays in memory and requires a host restart after process termination. Keep the flow in a sheet or full-screen cover and use its Close control to handle cancellation; the host controls any programmatic removal of the view.

## Session client

`VerificationSession` provides async `get()`, `upload()`, `submit()`, `createLivenessChallenge()`, `uploadBiometric()`, `submitFacial()`, `submitLocation()`, `requestCode()`, `confirmCode()`, `submitAnswers()`, `refresh()`, `replaceSession()` and `cancel()`. `SessionInfo.Profile.requirements` parses facial and location settings, including reference place labels, and the email and phone channels. `SessionInfo.nextStep` names the next outstanding step, `Questionnaire` evaluates `show_if` and checks answers, and `Rejection` maps a `422` to its spec screen. Uploads and submissions accept UUID retry keys. Reuse each key with unchanged evidence after a network interruption. Renew access through the authenticated host backend for the same case.

The client uses an ephemeral session without cookies, credential storage or response caching. It rejects redirects and requires HTTPS except on loopback development URLs. Timeouts cover the complete request and response. Session descriptions redact the bearer token. The UI checks configured file types and sizes; the backend remains authoritative.

The package has no external runtime dependencies. Add a local Swift package dependency on this repository and select the `CredflareSDK` product. No versioned release has been published.

## Example and checks

The native example connects to the local demo backend on port 3107. It requests a fresh session when Start is pressed. Pass `-session-url <url>` as a launch argument to request sessions from another local server. Host apps must declare `NSCameraUsageDescription` (documents and the liveness challenge) and `NSLocationWhenInUseUsageDescription` (location step). The challenge video has no audio track, so no microphone permission is needed. The example allows HTTP loopback networking only for local development and exposes synthetic documents through Files.

```sh
swift test
xcodebuild -project Examples/CredflareExample.xcodeproj -scheme CredflareExample -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run `./scripts/check-spec.sh` with `sdk-spec` checked out next to this repository to confirm the generated constants and copied fixtures match the spec. See [TESTING.md](TESTING.md) for the full test matrix and [docs/SDK-FLOW.md](docs/SDK-FLOW.md) for the screen flow.

The iOS simulator has no usable camera. The liveness logic is tested with an injected face signal provider; a run on a physical device is still required before release.

## Spec

Copy, colour tokens, icons, liveness rules and location limits come from `Sources/CredflareSDK/Spec.generated.swift`, generated from the shared `sdk-spec` repository. Never edit it by hand:

```sh
node ../sdk-spec/scripts/generate.mjs --target swift --out Sources/CredflareSDK/Spec.generated.swift
```

## Facial and location steps

Choose the compliance profile on your server when creating the case. The SDK collects outstanding documents first, then runs the facial and location requirements in profile order, and shows a receipt once nothing required is left.

The facial step asks the server for a liveness challenge, shows a mirrored front camera preview, guides the applicant into position and runs the server's gestures in order. It keeps a frame when each gesture completes, records the challenge window as a short silent H.264 video when the challenge asks for one, then takes a full resolution selfie photo (capped at 1600 pixels) and submits everything against the challenge. A timeout or expiry requests a new challenge on retry. Face signals come from a `FaceSignalProvider`; the default `VisionFaceSignalProvider` uses Apple Vision, and you can pass another provider to `CredflareVerificationView`.

The location step explains what is shared, names the requested place by its label when one is configured, asks for permission and waits for a fix within the configured accuracy and age. Simulated locations are reported where iOS detects them. The server makes every place decision; the SDK never receives place coordinates and never calls a geocoding or IP service.
