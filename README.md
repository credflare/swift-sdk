# Credflare Swift SDK

Native iOS document and selfie collection and an async applicant session client. Development SDK for iOS 16 and newer, distributed as a Swift package. Requires scoped-session backend support.

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

Camera source is client-reported. Trusted camera, liveness and deepfake checks are unavailable. Forms and location collection require a host flow. Unsent evidence stays in memory and requires a host restart after process termination. Keep the flow in a sheet or full-screen cover and use its Close control to handle cancellation; the host controls any programmatic removal of the view.

## Session client

`VerificationSession` provides async `get()`, `upload()`, `submit()`, `replaceSession()` and `cancel()`. Uploads and submissions accept UUID retry keys. Reuse each key with unchanged evidence after a network interruption. Renew access through the authenticated host backend for the same case.

The client uses an ephemeral session without cookies, credential storage or response caching. It rejects redirects and requires HTTPS except on loopback development URLs. Timeouts cover the complete request and response. Session descriptions redact the bearer token. The UI checks configured file types and sizes; the backend remains authoritative.

The package has no external runtime dependencies. Add a local Swift package dependency on this repository and select the `CredflareSDK` product. No versioned release has been published.

## Example and checks

The native example connects to the local demo backend on port 3107. It requests a fresh session when Start is pressed. Add `NSCameraUsageDescription` to any host app using camera capture. The example allows HTTP loopback networking only for local development and exposes synthetic documents through Files.

```sh
swift test
xcodebuild -project Examples/CredflareExample.xcodeproj -scheme CredflareExample -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The HTTP contract tests require Node.js, use captured API responses and start their own local fixture server. They cover capture rules, upload metadata, session authentication, request timeouts, interrupted response bodies, redirect rejection and descriptor validation.

Physical-device capture, permission recovery and interrupted device uploads require additional testing before release. The iOS simulator has no usable camera; use file uploads there.

## Developer-configured facial collection

Choose the compliance profile on your server when creating the case. The recipient does not choose a profile or verification mode. The SDK collects outstanding documents first, then opens the selfie step only when the case requests `facial_verification`. Selfie-only cases go directly to that step. Document alternatives and capture-source choices follow the server's requirement rules.

The selfie step uses the front camera, provides a preview and retake action, and sends only after confirmation. Uploads use the scoped biometric endpoint; facial submissions reference the uploaded file ID. Retrying a send reuses its upload and submission keys. A receipt confirms collection for review, not a face match or liveness result.

The backend currently reports liveness, trusted camera and deepfake detection as unavailable. Automated face matching and validated liveness processing are not implemented by this capture interface. Forms and location checks return control to the host app. Example apps obtain their requirements from the demo server without a recipient-facing profile selector.
