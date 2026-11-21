# SDK flow

`CredflareVerificationView` drives one applicant session from start to receipt. All screens use the generated spec copy, tokens and icons, centre every line of text and follow the system light or dark appearance.

## Screens

1. **Intro.** Loads the session through the host's session provider. Shows a retry when the session cannot start.
2. **Documents.** Lists each outstanding document as a centred card with its capture method. Notes when a selfie step or host steps follow.
3. **Capture and review.** For each requested side: instruction, photo or file, preview, then a review of every item before sending. Leaving with unsent items asks for confirmation.
4. **Facial step** (when the profile has `facial_verification`).
   1. Intro with the number of movements, guidance, the recording consent line when `record_video` is on, and the privacy line naming the requester.
   2. Camera permission, then `POST /sdk/sessions/{session}/liveness-challenges`.
   3. Live front camera preview, mirrored on screen only. Frames are analysed every `sample_interval_ms` in the unmirrored portrait image.
   4. Position gate with the spec hints, then each gesture in the server's order with its prompt and per gesture timeout. Losing the face shows the face lost hint.
   5. A JPEG frame is kept when each gesture completes. When the challenge records video, an H.264 mp4 of about 480p with no audio is written for at most `max_video_seconds`.
   6. A selfie is taken from the next centred, neutral frame.
   7. Uploads: one `gesture` frame per gesture, the `liveness_video`, then the `selfie`, each with the challenge ID, `capture_source=camera` and its own idempotency key. Then the facial submission.
   8. Timeout, expiry or a rejected submission shows the reason and a retry that requests a new challenge. A network failure while sending retries the same uploads with the same keys.
5. **Location step** (when the profile has `location_verification`).
   1. Consent with the spec copy. With a reference place the title and requirement name the place labels only.
   2. When in use permission, then Core Location updates at best accuracy until a fix is within `max_accuracy_m` and younger than `max_age_s`, or `fix_timeout_s` passes.
   3. The applicant reviews accuracy, coordinates and time, then sends. `is_mock` comes from `sourceInformation.isSimulatedBySoftware` and is `null` when iOS gives no source information. Provider is `gps`.
   4. A `422` shows the server's reason with a retry. After `retry_attempts` failed fixes the screen asks the applicant to contact the requester.
6. **Receipt.** Lists each item received in this session. Form fields still needed return control to the host with `hostActionRequired`.

## Face signals

`VisionFaceSignalProvider` runs `VNDetectFaceRectanglesRequest` and `VNDetectFaceLandmarksRequest`, both revision 3, on each analysed frame.

| Signal | Source |
| --- | --- |
| `box` | Face bounding box converted from Vision's lower left origin to a top left origin |
| `yaw` | Vision yaw in degrees, same sign: negative when the person turns to their own right |
| `pitch` | Vision pitch in degrees with the sign flipped: Vision reports head down as positive |
| `eye_open` | Eye landmark height over width, relative to the applicant's own median over the first frames |
| `smile` | Mouth width over pupil distance, relative to the applicant's own neutral median |

Vision has no eye or smile probabilities, so both are derived from landmark geometry and normalized to 0 to 1. The spec `vision` thresholds are the defaults.

## Permissions

| Key | Used for |
| --- | --- |
| `NSCameraUsageDescription` | Document photos and the facial step |
| `NSLocationWhenInUseUsageDescription` | The location step |

No microphone permission is needed.
