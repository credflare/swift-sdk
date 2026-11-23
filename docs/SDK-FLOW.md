# SDK flow

`CredflareVerificationView` drives one applicant session from start to receipt. All screens use the generated spec copy, tokens and icons, centre every line of text and follow the system light or dark appearance.

## Screens

1. **Intro.** Loads the session through the host's session provider. Shows a retry when the session cannot start.
2. **Documents.** Lists each outstanding document as a centred card with its capture method. Notes when a selfie step or further steps follow.
3. **Capture and review.** For each requested side: instruction, photo or file, preview, then a review of every item before sending. Leaving with unsent items asks for confirmation.
4. **Facial step** (when the profile has `facial_verification`).
   1. Intro with the number of movements, guidance, the recording consent line when `record_video` is on, and the privacy line naming the requester.
   2. Camera permission, then `POST /sdk/sessions/{session}/liveness-challenges`.
   3. Live front camera preview, mirrored on screen only. Frames are analysed every `sample_interval_ms` in the unmirrored portrait image.
   4. Position gate with the spec hints, then each gesture in the server's order with its prompt and per gesture timeout. Losing the face shows the face lost hint.
   5. A JPEG frame is kept when each gesture completes. When the challenge records video, an H.264 mp4 scaled to 480 pixels on the short edge, with no audio, is written for at most `max_video_seconds`.
   6. Once the next frame is centred and neutral, a full resolution photo is taken on the same camera session and scaled to at most 1600 pixels on the long edge. If the photo fails, that analysed frame is used instead.
   7. Uploads: one `gesture` frame per gesture, the `liveness_video`, then the `selfie`, each with the challenge ID, `capture_source=camera` and its own idempotency key. Then the facial submission.
   8. Timeout or expiry shows the reason and a retry that requests a new challenge. A rejected submission shows the rejection screen for its `code` (see Rejections) with Start again, which requests a new challenge. A network failure while sending retries the same uploads with the same keys.
5. **Location step** (when the profile has `location_verification`).
   1. Consent with the spec copy. With a reference place the title and requirement name the place labels only.
   2. When in use permission, then Core Location updates at best accuracy until a fix is within `max_accuracy_m` and younger than `max_age_s`, or `fix_timeout_s` passes.
   3. The applicant reviews accuracy, coordinates and time, then sends. `is_mock` comes from `sourceInformation.isSimulatedBySoftware` and is `null` when iOS gives no source information. Provider is `gps`.
   4. A `422` shows the rejection screen for its `code`. With reference places, the place message replaces the message and names the place labels. Try again takes a new fix with a new idempotency key. After `retry_attempts` failed fixes the screen asks the applicant to contact the requester.
6. **Questions** (when `form_schema` lists questions of supported types). Each question type has its own control: text fields, a number field checked against `min` and `max`, a date picker, email and phone fields, menus for single choice and country, check boxes for multiple choice and consent, and a list of names with an "I am one of the founders" choice for founders. A question whose `show_if` does not hold for the answers above it, or for the earlier answers in `form_answers`, is not shown, not checked and not sent. Earlier answers are never sent again unless their question is asked again, when they are its starting value. Conditions read the same trimmed values that are sent, and numbers are sent as the text typed. Required, format and range errors appear under each question. The answers go to `submit` as `form_submission` with one idempotency key per set of answers.
7. **Email and phone codes** (when the profile has `email_verification` or `phone_verification`). The applicant enters the address or number (phone numbers in international format, spaces and punctuation removed), then the six digit code. The code screen names the masked destination, counts down to `resend_available_at` before offering a new code, shows the codes left, and lets the applicant change the destination.
8. **Receipt.** Lists each item received in this session. Shown questions of types the SDK does not ask, or checks it does not run, return control to the host with `hostActionRequired`.

## Order and refresh

Documents come first, then questions, then checks in profile order. After every submit and code confirmation the view fetches the session again and continues with whatever is still outstanding, so a requirement a workflow adds mid case appears as the next step. The receipt shows only when the case is no longer open or nothing is outstanding; a closed case (`409`) also ends at the receipt. When the fetch fails, the view shows `errors.refresh_failed` with Try again and never the receipt.

## Rejections

Every `422` with a known `code` shows the title, message and action from the spec rejection map, with `{verifier}` filled from `requester.name` or the fallback, plus the requested by and help lines. Actions: Try again stays on the step, Start again requests a new challenge, Enter the code again clears the code, Send a new code requests one for the same destination, the wait action returns to the code screen with its countdown, and Close ends the flow with `hostActionRequired(code:)` carrying the rejection code. Leaving such a screen through the header Close ends the same way. A `422` without a code or with an unknown code shows the server message with Try again.

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
