// GENERATED FILE, DO NOT EDIT.
// Source: credflare sdk-spec 1.0.0 (13c02ea43d7a). Regenerate with scripts/generate.mjs.

/// One step of a gesture. value and holdFrames name a threshold key.
public struct SpecGestureStep: Equatable, Sendable {
    public let signal: String
    public let op: String
    public let value: String
    public let holdFrames: String?
}

/// One setting in the requirement settings schema. path uses dots, with [] for list items. defaultJson is the JSON encoded default.
public struct SpecSetting: Equatable, Sendable {
    public let path: String
    public let type: String
    public let optional: Bool
    public let min: Double?
    public let max: Double?
    public let options: [String]
    public let defaultJson: String?
}

public struct SpecPalette: Equatable, Sendable {
    public let primary: UInt32
    public let onPrimary: UInt32
    public let surface: UInt32
    public let ink: UInt32
    public let muted: UInt32
    public let soft: UInt32
    public let border: UInt32
    public let accent: UInt32
    public let success: UInt32
    public let error: UInt32
    public let warningSoft: UInt32
    public let warningInk: UInt32
}

public struct SpecTextStyle: Equatable, Sendable {
    public let size: Double
    public let lineHeight: Double
    public let weight: Int
}

/// Absolute path data using only M, L, C and Z, with values in viewBox units.
public struct SpecIconPath: Equatable, Sendable {
    public let d: String
    public let stroke: Bool
    public let fill: Bool
    public let strokeWidth: Double
    public let strokeOpacity: Double
    public let fillOpacity: Double
}

public struct SpecIcon: Equatable, Sendable {
    public let viewBox: Double
    public let strokeWidth: Double
    public let paths: [SpecIconPath]
}

public enum CredflareSpec {
    public static let version = "1.0.0"
    public static let hash = "13c02ea43d7a"

    public enum Liveness {
        public static let version: Int = 1
        public static let challengeTtlS: Int = 120
        public static let gestureTimeoutMs: Int = 10000
        public static let sampleIntervalMs: Int = 66
        public static let videoMaxSeconds: Int = 8
        public static let videoMaxHeight: Int = 480
        public static let positionFaceAreaMin: Double = 0.15
        public static let positionFaceAreaMax: Double = 0.65
        public static let positionCenterTolerance: Double = 0.2
        public static let positionFaces: Int = 1
        public static let faceLostResetMs: Int = 1000
        public static let gestureNames: [String] = [
            "blink",
            "smile",
            "turn_left",
            "turn_right",
            "nod",
        ]
        public static let thresholds: [String: [String: Double]] = [
            "default": [
                "eye_open_baseline": 0.6,
                "eye_closed": 0.3,
                "eye_reopened": 0.5,
                "smile": 0.6,
                "smile_hold_frames": 5.0,
                "turn": 20.0,
                "nod": 15.0,
                "return": 10.0,
            ],
            "mediapipe": [
                "smile": 0.4,
            ],
            "mlkit": [
                "smile": 0.7,
            ],
            "vision": [:],
        ]
        public static let gestures: [String: [SpecGestureStep]] = [
            "blink": [
                SpecGestureStep(
                    signal: "eye_open",
                    op: "gt",
                    value: "eye_open_baseline",
                    holdFrames: nil
                ),
                SpecGestureStep(
                    signal: "eye_open",
                    op: "lt",
                    value: "eye_closed",
                    holdFrames: nil
                ),
                SpecGestureStep(
                    signal: "eye_open",
                    op: "gt",
                    value: "eye_reopened",
                    holdFrames: nil
                ),
            ],
            "smile": [
                SpecGestureStep(
                    signal: "smile",
                    op: "gt",
                    value: "smile",
                    holdFrames: "smile_hold_frames"
                ),
            ],
            "turn_left": [
                SpecGestureStep(
                    signal: "yaw",
                    op: "gt",
                    value: "turn",
                    holdFrames: nil
                ),
                SpecGestureStep(
                    signal: "yaw",
                    op: "abs_lt",
                    value: "return",
                    holdFrames: nil
                ),
            ],
            "turn_right": [
                SpecGestureStep(
                    signal: "yaw",
                    op: "lt_neg",
                    value: "turn",
                    holdFrames: nil
                ),
                SpecGestureStep(
                    signal: "yaw",
                    op: "abs_lt",
                    value: "return",
                    holdFrames: nil
                ),
            ],
            "nod": [
                SpecGestureStep(
                    signal: "pitch",
                    op: "lt_neg",
                    value: "nod",
                    holdFrames: nil
                ),
                SpecGestureStep(
                    signal: "pitch",
                    op: "abs_lt",
                    value: "return",
                    holdFrames: nil
                ),
            ],
        ]
    }

    public enum Location {
        public static let version: Int = 1
        public static let clockSkewS: Int = 30
        public static let fixTimeoutS: Int = 30
        public static let retryAttempts: Int = 3
    }

    public enum Settings {
        public static let version: Int = 1
        public static let facialVerificationGesturesDefault: [String] = [
            "blink",
            "smile",
            "turn_left",
            "turn_right",
            "nod",
        ]
        public static let facialVerificationGestureCountDefault: Int = 3
        public static let facialVerificationRecordVideoDefault: Bool = true
        public static let facialVerificationVideoRetentionDaysDefault: Int = 30
        public static let locationVerificationMaxAccuracyMDefault: Int = 100
        public static let locationVerificationMaxAgeSDefault: Int = 60
        public static let locationVerificationMockLocationDefault: String = "reject"
        public static let locationVerificationIpCountryDefault: String = "flag"
        public static let schema: [SpecSetting] = [
            SpecSetting(
                path: "facial_verification.gestures",
                type: "set",
                optional: false,
                min: 1.0,
                max: nil,
                options: [
                    "blink",
                    "smile",
                    "turn_left",
                    "turn_right",
                    "nod",
                ],
                defaultJson: "[\"blink\",\"smile\",\"turn_left\",\"turn_right\",\"nod\"]"
            ),
            SpecSetting(
                path: "facial_verification.gesture_count",
                type: "int",
                optional: false,
                min: 1.0,
                max: 5.0,
                options: [],
                defaultJson: "3"
            ),
            SpecSetting(
                path: "facial_verification.record_video",
                type: "bool",
                optional: false,
                min: nil,
                max: nil,
                options: [],
                defaultJson: "true"
            ),
            SpecSetting(
                path: "facial_verification.video_retention_days",
                type: "int",
                optional: false,
                min: 1.0,
                max: 365.0,
                options: [],
                defaultJson: "30"
            ),
            SpecSetting(
                path: "location_verification.max_accuracy_m",
                type: "int",
                optional: false,
                min: 5.0,
                max: 5000.0,
                options: [],
                defaultJson: "100"
            ),
            SpecSetting(
                path: "location_verification.max_age_s",
                type: "int",
                optional: false,
                min: 5.0,
                max: 3600.0,
                options: [],
                defaultJson: "60"
            ),
            SpecSetting(
                path: "location_verification.mock_location",
                type: "enum",
                optional: false,
                min: nil,
                max: nil,
                options: [
                    "reject",
                    "flag",
                    "allow",
                ],
                defaultJson: "\"reject\""
            ),
            SpecSetting(
                path: "location_verification.ip_country",
                type: "enum",
                optional: false,
                min: nil,
                max: nil,
                options: [
                    "reject",
                    "flag",
                    "off",
                ],
                defaultJson: "\"flag\""
            ),
            SpecSetting(
                path: "location_verification.reference",
                type: "object",
                optional: true,
                min: nil,
                max: nil,
                options: [],
                defaultJson: "null"
            ),
            SpecSetting(
                path: "location_verification.reference.places",
                type: "list",
                optional: false,
                min: 1.0,
                max: 50.0,
                options: [],
                defaultJson: nil
            ),
            SpecSetting(
                path: "location_verification.reference.places[].id",
                type: "string",
                optional: false,
                min: nil,
                max: 64.0,
                options: [],
                defaultJson: nil
            ),
            SpecSetting(
                path: "location_verification.reference.places[].label",
                type: "string",
                optional: false,
                min: nil,
                max: 120.0,
                options: [],
                defaultJson: nil
            ),
            SpecSetting(
                path: "location_verification.reference.places[].latitude",
                type: "number",
                optional: false,
                min: -90.0,
                max: 90.0,
                options: [],
                defaultJson: nil
            ),
            SpecSetting(
                path: "location_verification.reference.places[].longitude",
                type: "number",
                optional: false,
                min: -180.0,
                max: 180.0,
                options: [],
                defaultJson: nil
            ),
            SpecSetting(
                path: "location_verification.reference.places[].radius_m",
                type: "int",
                optional: false,
                min: 0.0,
                max: 100000.0,
                options: [],
                defaultJson: nil
            ),
            SpecSetting(
                path: "location_verification.reference.rule",
                type: "enum",
                optional: false,
                min: nil,
                max: nil,
                options: [
                    "within",
                    "outside",
                ],
                defaultJson: "\"within\""
            ),
            SpecSetting(
                path: "location_verification.reference.match",
                type: "enum",
                optional: false,
                min: nil,
                max: nil,
                options: [
                    "any",
                    "all",
                ],
                defaultJson: "\"any\""
            ),
            SpecSetting(
                path: "location_verification.reference.confidence",
                type: "enum",
                optional: false,
                min: nil,
                max: nil,
                options: [
                    "strict",
                    "lenient",
                ],
                defaultJson: "\"strict\""
            ),
            SpecSetting(
                path: "location_verification.reference.on_mismatch",
                type: "enum",
                optional: false,
                min: nil,
                max: nil,
                options: [
                    "reject",
                    "flag",
                ],
                defaultJson: "\"reject\""
            ),
        ]
    }

    public enum Copy {
        public static let locales: [String] = [
            "en",
        ]
        public static let en: [String: String] = [
            "common.back": "Back",
            "common.cancel": "Cancel",
            "common.change": "Change",
            "common.close": "Close",
            "common.continue": "Continue",
            "common.done": "Done",
            "common.loading": "Getting ready…",
            "common.return_to_app": "Return to app",
            "common.secured_by": "Secured by Credflare",
            "common.start": "Start",
            "common.step_progress": "Step {current} of {total}",
            "common.test_mode": "Test mode",
            "common.try_again": "Try again",
            "common.verifier_fallback": "your verifier",
            "intro.title": "Verify your identity",
            "intro.body": "Follow the steps requested by {verifier}. Review each item before you send it.",
            "intro.start": "Start",
            "intro.checking": "Checking what is still needed…",
            "exit.title": "Leave for now?",
            "exit.body": "Evidence you already sent is kept. Unsent photos and files will be discarded. You can come back through the app that sent you here.",
            "exit.stay": "Keep going",
            "exit.leave": "Leave for now",
            "exit.discard_title": "Discard these photos and files?",
            "exit.discard_body": "You have not sent this document yet.",
            "exit.discard_stay": "Keep editing",
            "exit.discard_leave": "Discard",
            "documents.title": "Documents requested",
            "documents.requested_by": "Requested by {verifier}.",
            "documents.back": "Documents",
            "documents.section_required": "Required",
            "documents.section_one_of": "Provide one of these",
            "documents.section_count_of": "Provide {count} of these",
            "documents.method_camera": "Camera photos",
            "documents.method_upload": "Saved files",
            "documents.method_either": "Photo or file",
            "documents.method_both": "Photo and saved file",
            "documents.unavailable": "Not available in this app. Contact {verifier}.",
            "documents.selfie_next": "After your documents, you will take a selfie.",
            "documents.location_next": "After your documents, you will share your location.",
            "documents.selfie_location_next": "After your documents, you will take a selfie and share your location.",
            "documents.location_selfie_next": "After your documents, you will share your location and take a selfie.",
            "documents.host_steps_next": "After your documents, the app will guide you through the remaining steps.",
            "capture.side_front": "Front",
            "capture.side_back": "Back",
            "capture.source_camera": "Camera photo",
            "capture.source_upload": "Saved file",
            "capture.instruction_camera": "Place the {document} on a flat surface. Keep all four corners visible and avoid glare.",
            "capture.instruction_either": "Take a photo or choose a saved file of the {side}.",
            "capture.instruction_upload": "Choose a clear photo or scan of the {side}.",
            "capture.instruction_upload_pdf": "Choose a clear photo, scan or PDF of the {side}.",
            "capture.also_saved_file": "You also need to add a saved file of each side.",
            "capture.check_photo": "Check that all four corners are visible, the text is sharp and there is no glare.",
            "capture.take_photo": "Take photo",
            "capture.choose_file": "Choose a file",
            "capture.retake_photo": "Retake photo",
            "capture.change_file": "Change file",
            "capture.use_file_instead": "Use a file instead",
            "capture.use_photo_instead": "Take a photo instead",
            "capture.file_limits": "{types}, up to {size}",
            "capture.preview_pdf": "PDF",
            "capture.preview_document": "Document",
            "capture.preview_label": "Preview of the {side}",
            "review.title": "Review before sending",
            "review.body": "Check each photo and file before you send them.",
            "review.item": "{side} · {source}",
            "review.change": "Change",
            "review.send": "Send document",
            "sending.uploading": "Uploading…",
            "sending.uploading_progress": "Uploading {current} of {total}…",
            "sending.sending": "Sending…",
            "sending.sent_title": "Your evidence was sent",
            "sending.sent_body": "We are checking that everything arrived.",
            "sending.check_again": "Check again",
            "receipt.title": "Evidence received",
            "receipt.body": "Your evidence will be reviewed by {verifier}. You can close this screen.",
            "receipt.document": "{document} received",
            "receipt.selfie": "Selfie received",
            "receipt.location": "Location received",
            "receipt.host_steps": "The app will guide you through the remaining steps.",
            "receipt.done": "Done",
            "selfie.title": "Take a selfie",
            "selfie.guidance": "Face the camera in even light. Keep your whole face visible and remove anything covering it.",
            "selfie.tip_face_camera": "Face the camera directly.",
            "selfie.tip_light": "Find even light on your face.",
            "selfie.tip_neutral": "Keep a neutral expression.",
            "selfie.tip_glasses": "Take off glasses if you can.",
            "selfie.open_camera": "Open front camera",
            "selfie.starting_camera": "Starting the camera…",
            "selfie.take": "Take selfie",
            "selfie.review_title": "Review your selfie",
            "selfie.review_body": "Make sure your face is clear and fully visible before you send it.",
            "selfie.retake": "Retake selfie",
            "selfie.send": "Send selfie",
            "selfie.sending": "Sending your selfie…",
            "selfie.preview_label": "Your selfie preview",
            "selfie.privacy": "Your selfie will be sent to {verifier} for review.",
            "liveness.title": "Follow the prompts",
            "liveness.body": "You will be asked to make {total} simple movements. Keep your face inside the frame.",
            "liveness.start": "Start",
            "liveness.progress": "Movement {current} of {total}",
            "liveness.position.no_face": "Look at the camera",
            "liveness.position.move_closer": "Move closer",
            "liveness.position.move_further": "Move back a little",
            "liveness.position.center": "Center your face in the frame",
            "liveness.position.one_face": "Make sure only your face is in the frame",
            "liveness.position.hold_still": "Hold still",
            "liveness.position.more_light": "Move to a brighter place",
            "liveness.position.ready": "Good. Hold still",
            "liveness.gesture.blink": "Blink",
            "liveness.gesture.smile": "Smile",
            "liveness.gesture.turn_left": "Slowly turn your head to your left, then back",
            "liveness.gesture.turn_right": "Slowly turn your head to your right, then back",
            "liveness.gesture.nod": "Nod: look down, then back up",
            "liveness.gesture_done": "Done",
            "liveness.face_lost": "We lost sight of your face. Look at the camera.",
            "liveness.success": "All movements recorded",
            "liveness.timeout": "Time ran out for this movement.",
            "liveness.expired": "This step timed out. Start it again.",
            "liveness.retry": "Try again",
            "liveness.sending": "Sending your recording…",
            "video.consent": "This step records a short video of your face. It is sent to {verifier} for review.",
            "video.recording": "Recording",
            "location.title": "Share your location",
            "location.why": "{verifier} asks where you are right now. Your location is used only for this request.",
            "location.what_shared": "We send your coordinates, how accurate they are and when they were taken.",
            "location.permission_prompt": "Your device will ask for permission. Choose Allow.",
            "location.share": "Share location",
            "location.waiting": "Finding your location…",
            "location.waiting_accuracy": "Getting a more accurate reading. Stay where you are, near a window or outside if you can.",
            "location.found_title": "Location found",
            "location.found_body": "Check it looks right, then send it.",
            "location.accuracy_label": "Accuracy",
            "location.accuracy_value": "Within {meters} m",
            "location.coordinates_label": "Coordinates",
            "location.time_label": "Taken at",
            "location.send": "Send location",
            "location.permission_denied": "Location access is off. Turn it on in Settings, then try again.",
            "location.permission_denied_browser": "Location access is blocked. Allow it for this site in your browser settings, then reload the page.",
            "location.unavailable": "Location is not available on this device.",
            "location.timeout": "We could not find your location in time. Try again.",
            "location.low_accuracy": "Your location is not accurate enough yet. Move near a window or outside, then try again.",
            "location.mock_detected": "An app or setting is changing your device location. Turn it off, then try again.",
            "location.retry": "Try again",
            "location.retries_exhausted": "We could not get your location. Contact {verifier}.",
            "location.place.title_within": "Share your location at {place}",
            "location.place.title_outside": "Share your location away from {place}",
            "location.place.need_within": "You need to be at {place}.",
            "location.place.need_within_any": "You need to be at one of these places: {places}.",
            "location.place.need_within_all": "You need to be at each of these places: {places}.",
            "location.place.need_outside": "You need to be away from {place}.",
            "location.place.need_outside_all": "You need to be away from these places: {places}.",
            "location.place.need_outside_any": "You need to be away from at least one of these places: {places}.",
            "location.place.not_matched_within": "You do not seem to be at {place} yet. Move closer, then try again.",
            "location.place.not_matched_outside": "You seem to be too close to {place}. Move away, then try again.",
            "location.place.not_precise": "Your location is not precise enough to check this place. Move near a window or outside, then try again.",
            "location.place.rejected": "Your location does not match the place requested by {verifier}. Try again from the right place.",
            "location.place.retry": "Try again",
            "errors.generic": "Something went wrong. Try again.",
            "errors.network": "Could not connect. Check your connection and try again.",
            "errors.session_expired": "Your session has expired. Close this screen and start again.",
            "errors.start_failed": "We could not start. Check your connection and try again.",
            "errors.refresh_failed": "We could not check what is still needed. Try again.",
            "errors.camera_denied": "Camera access is off. Turn it on in Settings, then try again.",
            "errors.camera_denied_browser": "Camera access is blocked. Allow it in your browser settings, then try again.",
            "errors.camera_unavailable": "The camera is unavailable. Try again on a device with a camera.",
            "errors.front_camera_required": "This step needs a front camera. Try another device.",
            "errors.camera_no_photo": "The camera did not return a readable photo. Try again.",
            "errors.file_unreadable": "This file could not be read. Choose another file.",
            "errors.file_type": "Choose a {types} file.",
            "errors.file_too_large": "This file is larger than {size}. Choose a smaller file.",
            "errors.file_empty": "This file is empty. Choose another file.",
            "errors.photo_format": "This photo format is not accepted by {verifier}.",
            "errors.photo_invalid": "This photo is empty or too large. Retake it.",
            "errors.document_unsupported": "This document cannot be collected in this app. Contact {verifier}.",
            "errors.add_file_failed": "Could not add this file. Try again.",
            "errors.send_document_failed": "Could not send this document. Check your connection and try again.",
            "errors.selfie_failed": "Could not take your selfie. Try again.",
            "errors.send_selfie_failed": "Could not send your selfie. Check your connection and try again.",
            "errors.challenge_failed": "We could not start this step. Check your connection and try again.",
            "errors.send_location_failed": "Could not send your location. Check your connection and try again.",
        ]
    }

    public enum CopyKey {
        public static let commonBack: String = "common.back"
        public static let commonCancel: String = "common.cancel"
        public static let commonChange: String = "common.change"
        public static let commonClose: String = "common.close"
        public static let commonContinue: String = "common.continue"
        public static let commonDone: String = "common.done"
        public static let commonLoading: String = "common.loading"
        public static let commonReturnToApp: String = "common.return_to_app"
        public static let commonSecuredBy: String = "common.secured_by"
        public static let commonStart: String = "common.start"
        public static let commonStepProgress: String = "common.step_progress"
        public static let commonTestMode: String = "common.test_mode"
        public static let commonTryAgain: String = "common.try_again"
        public static let commonVerifierFallback: String = "common.verifier_fallback"
        public static let introTitle: String = "intro.title"
        public static let introBody: String = "intro.body"
        public static let introStart: String = "intro.start"
        public static let introChecking: String = "intro.checking"
        public static let exitTitle: String = "exit.title"
        public static let exitBody: String = "exit.body"
        public static let exitStay: String = "exit.stay"
        public static let exitLeave: String = "exit.leave"
        public static let exitDiscardTitle: String = "exit.discard_title"
        public static let exitDiscardBody: String = "exit.discard_body"
        public static let exitDiscardStay: String = "exit.discard_stay"
        public static let exitDiscardLeave: String = "exit.discard_leave"
        public static let documentsTitle: String = "documents.title"
        public static let documentsRequestedBy: String = "documents.requested_by"
        public static let documentsBack: String = "documents.back"
        public static let documentsSectionRequired: String = "documents.section_required"
        public static let documentsSectionOneOf: String = "documents.section_one_of"
        public static let documentsSectionCountOf: String = "documents.section_count_of"
        public static let documentsMethodCamera: String = "documents.method_camera"
        public static let documentsMethodUpload: String = "documents.method_upload"
        public static let documentsMethodEither: String = "documents.method_either"
        public static let documentsMethodBoth: String = "documents.method_both"
        public static let documentsUnavailable: String = "documents.unavailable"
        public static let documentsSelfieNext: String = "documents.selfie_next"
        public static let documentsLocationNext: String = "documents.location_next"
        public static let documentsSelfieLocationNext: String = "documents.selfie_location_next"
        public static let documentsLocationSelfieNext: String = "documents.location_selfie_next"
        public static let documentsHostStepsNext: String = "documents.host_steps_next"
        public static let captureSideFront: String = "capture.side_front"
        public static let captureSideBack: String = "capture.side_back"
        public static let captureSourceCamera: String = "capture.source_camera"
        public static let captureSourceUpload: String = "capture.source_upload"
        public static let captureInstructionCamera: String = "capture.instruction_camera"
        public static let captureInstructionEither: String = "capture.instruction_either"
        public static let captureInstructionUpload: String = "capture.instruction_upload"
        public static let captureInstructionUploadPdf: String = "capture.instruction_upload_pdf"
        public static let captureAlsoSavedFile: String = "capture.also_saved_file"
        public static let captureCheckPhoto: String = "capture.check_photo"
        public static let captureTakePhoto: String = "capture.take_photo"
        public static let captureChooseFile: String = "capture.choose_file"
        public static let captureRetakePhoto: String = "capture.retake_photo"
        public static let captureChangeFile: String = "capture.change_file"
        public static let captureUseFileInstead: String = "capture.use_file_instead"
        public static let captureUsePhotoInstead: String = "capture.use_photo_instead"
        public static let captureFileLimits: String = "capture.file_limits"
        public static let capturePreviewPdf: String = "capture.preview_pdf"
        public static let capturePreviewDocument: String = "capture.preview_document"
        public static let capturePreviewLabel: String = "capture.preview_label"
        public static let reviewTitle: String = "review.title"
        public static let reviewBody: String = "review.body"
        public static let reviewItem: String = "review.item"
        public static let reviewChange: String = "review.change"
        public static let reviewSend: String = "review.send"
        public static let sendingUploading: String = "sending.uploading"
        public static let sendingUploadingProgress: String = "sending.uploading_progress"
        public static let sendingSending: String = "sending.sending"
        public static let sendingSentTitle: String = "sending.sent_title"
        public static let sendingSentBody: String = "sending.sent_body"
        public static let sendingCheckAgain: String = "sending.check_again"
        public static let receiptTitle: String = "receipt.title"
        public static let receiptBody: String = "receipt.body"
        public static let receiptDocument: String = "receipt.document"
        public static let receiptSelfie: String = "receipt.selfie"
        public static let receiptLocation: String = "receipt.location"
        public static let receiptHostSteps: String = "receipt.host_steps"
        public static let receiptDone: String = "receipt.done"
        public static let selfieTitle: String = "selfie.title"
        public static let selfieGuidance: String = "selfie.guidance"
        public static let selfieTipFaceCamera: String = "selfie.tip_face_camera"
        public static let selfieTipLight: String = "selfie.tip_light"
        public static let selfieTipNeutral: String = "selfie.tip_neutral"
        public static let selfieTipGlasses: String = "selfie.tip_glasses"
        public static let selfieOpenCamera: String = "selfie.open_camera"
        public static let selfieStartingCamera: String = "selfie.starting_camera"
        public static let selfieTake: String = "selfie.take"
        public static let selfieReviewTitle: String = "selfie.review_title"
        public static let selfieReviewBody: String = "selfie.review_body"
        public static let selfieRetake: String = "selfie.retake"
        public static let selfieSend: String = "selfie.send"
        public static let selfieSending: String = "selfie.sending"
        public static let selfiePreviewLabel: String = "selfie.preview_label"
        public static let selfiePrivacy: String = "selfie.privacy"
        public static let livenessTitle: String = "liveness.title"
        public static let livenessBody: String = "liveness.body"
        public static let livenessStart: String = "liveness.start"
        public static let livenessProgress: String = "liveness.progress"
        public static let livenessPositionNoFace: String = "liveness.position.no_face"
        public static let livenessPositionMoveCloser: String = "liveness.position.move_closer"
        public static let livenessPositionMoveFurther: String = "liveness.position.move_further"
        public static let livenessPositionCenter: String = "liveness.position.center"
        public static let livenessPositionOneFace: String = "liveness.position.one_face"
        public static let livenessPositionHoldStill: String = "liveness.position.hold_still"
        public static let livenessPositionMoreLight: String = "liveness.position.more_light"
        public static let livenessPositionReady: String = "liveness.position.ready"
        public static let livenessGestureBlink: String = "liveness.gesture.blink"
        public static let livenessGestureSmile: String = "liveness.gesture.smile"
        public static let livenessGestureTurnLeft: String = "liveness.gesture.turn_left"
        public static let livenessGestureTurnRight: String = "liveness.gesture.turn_right"
        public static let livenessGestureNod: String = "liveness.gesture.nod"
        public static let livenessGestureDone: String = "liveness.gesture_done"
        public static let livenessFaceLost: String = "liveness.face_lost"
        public static let livenessSuccess: String = "liveness.success"
        public static let livenessTimeout: String = "liveness.timeout"
        public static let livenessExpired: String = "liveness.expired"
        public static let livenessRetry: String = "liveness.retry"
        public static let livenessSending: String = "liveness.sending"
        public static let videoConsent: String = "video.consent"
        public static let videoRecording: String = "video.recording"
        public static let locationTitle: String = "location.title"
        public static let locationWhy: String = "location.why"
        public static let locationWhatShared: String = "location.what_shared"
        public static let locationPermissionPrompt: String = "location.permission_prompt"
        public static let locationShare: String = "location.share"
        public static let locationWaiting: String = "location.waiting"
        public static let locationWaitingAccuracy: String = "location.waiting_accuracy"
        public static let locationFoundTitle: String = "location.found_title"
        public static let locationFoundBody: String = "location.found_body"
        public static let locationAccuracyLabel: String = "location.accuracy_label"
        public static let locationAccuracyValue: String = "location.accuracy_value"
        public static let locationCoordinatesLabel: String = "location.coordinates_label"
        public static let locationTimeLabel: String = "location.time_label"
        public static let locationSend: String = "location.send"
        public static let locationPermissionDenied: String = "location.permission_denied"
        public static let locationPermissionDeniedBrowser: String = "location.permission_denied_browser"
        public static let locationUnavailable: String = "location.unavailable"
        public static let locationTimeout: String = "location.timeout"
        public static let locationLowAccuracy: String = "location.low_accuracy"
        public static let locationMockDetected: String = "location.mock_detected"
        public static let locationRetry: String = "location.retry"
        public static let locationRetriesExhausted: String = "location.retries_exhausted"
        public static let locationPlaceTitleWithin: String = "location.place.title_within"
        public static let locationPlaceTitleOutside: String = "location.place.title_outside"
        public static let locationPlaceNeedWithin: String = "location.place.need_within"
        public static let locationPlaceNeedWithinAny: String = "location.place.need_within_any"
        public static let locationPlaceNeedWithinAll: String = "location.place.need_within_all"
        public static let locationPlaceNeedOutside: String = "location.place.need_outside"
        public static let locationPlaceNeedOutsideAll: String = "location.place.need_outside_all"
        public static let locationPlaceNeedOutsideAny: String = "location.place.need_outside_any"
        public static let locationPlaceNotMatchedWithin: String = "location.place.not_matched_within"
        public static let locationPlaceNotMatchedOutside: String = "location.place.not_matched_outside"
        public static let locationPlaceNotPrecise: String = "location.place.not_precise"
        public static let locationPlaceRejected: String = "location.place.rejected"
        public static let locationPlaceRetry: String = "location.place.retry"
        public static let errorsGeneric: String = "errors.generic"
        public static let errorsNetwork: String = "errors.network"
        public static let errorsSessionExpired: String = "errors.session_expired"
        public static let errorsStartFailed: String = "errors.start_failed"
        public static let errorsRefreshFailed: String = "errors.refresh_failed"
        public static let errorsCameraDenied: String = "errors.camera_denied"
        public static let errorsCameraDeniedBrowser: String = "errors.camera_denied_browser"
        public static let errorsCameraUnavailable: String = "errors.camera_unavailable"
        public static let errorsFrontCameraRequired: String = "errors.front_camera_required"
        public static let errorsCameraNoPhoto: String = "errors.camera_no_photo"
        public static let errorsFileUnreadable: String = "errors.file_unreadable"
        public static let errorsFileType: String = "errors.file_type"
        public static let errorsFileTooLarge: String = "errors.file_too_large"
        public static let errorsFileEmpty: String = "errors.file_empty"
        public static let errorsPhotoFormat: String = "errors.photo_format"
        public static let errorsPhotoInvalid: String = "errors.photo_invalid"
        public static let errorsDocumentUnsupported: String = "errors.document_unsupported"
        public static let errorsAddFileFailed: String = "errors.add_file_failed"
        public static let errorsSendDocumentFailed: String = "errors.send_document_failed"
        public static let errorsSelfieFailed: String = "errors.selfie_failed"
        public static let errorsSendSelfieFailed: String = "errors.send_selfie_failed"
        public static let errorsChallengeFailed: String = "errors.challenge_failed"
        public static let errorsSendLocationFailed: String = "errors.send_location_failed"
    }

    public enum ErrorCode {
        public static let locationAccuracy: String = "location.accuracy"
        public static let locationStale: String = "location.stale"
        public static let locationMock: String = "location.mock"
        public static let locationIpCountry: String = "location.ip_country"
        public static let locationReferenceNotMatched: String = "location.reference_not_matched"
        public static let livenessChallengeInvalid: String = "liveness.challenge_invalid"
        public static let livenessChallengeExpired: String = "liveness.challenge_expired"
        public static let livenessChallengeUsed: String = "liveness.challenge_used"
        public static let livenessGestureMismatch: String = "liveness.gesture_mismatch"
        public static let livenessFrameOutOfWindow: String = "liveness.frame_out_of_window"
        public static let livenessNotCamera: String = "liveness.not_camera"
        public static let livenessVideoMissing: String = "liveness.video_missing"
        public static let livenessVideoTooLong: String = "liveness.video_too_long"
        public static let livenessVideoUnreadable: String = "liveness.video_unreadable"
        public static let meanings: [String: String] = [
            "location.accuracy": "Accuracy is missing or larger than max_accuracy_m",
            "location.stale": "fix_time is missing, older than max_age_s plus clock_skew_s, or in the future",
            "location.mock": "is_mock is true and mock_location is reject",
            "location.ip_country": "The IP country does not match and ip_country is reject",
            "location.reference_not_matched": "The place rule failed and on_mismatch is reject",
            "liveness.challenge_invalid": "The challenge is unknown, belongs to another case or was replaced",
            "liveness.challenge_expired": "The challenge expired",
            "liveness.challenge_used": "The challenge was already used",
            "liveness.gesture_mismatch": "A gesture frame is missing, extra, out of order or for a gesture the challenge does not include",
            "liveness.frame_out_of_window": "A file was uploaded before the challenge was issued or after it expired",
            "liveness.not_camera": "Evidence was not uploaded with capture_source=camera for this challenge",
            "liveness.video_missing": "record_video is on and no video for this challenge was sent",
            "liveness.video_too_long": "The video is longer than max_video_seconds plus one second",
            "liveness.video_unreadable": "The server cannot read the video duration",
        ]
    }

    public enum Tokens {
        public static let light: SpecPalette = SpecPalette(
            primary: 0xFF20315F,
            onPrimary: 0xFFFFFFFF,
            surface: 0xFFFFFFFF,
            ink: 0xFF18233C,
            muted: 0xFF52617A,
            soft: 0xFFF0F3FA,
            border: 0xFFCAD4E5,
            accent: 0xFFDC6E11,
            success: 0xFF126749,
            error: 0xFFAA2525,
            warningSoft: 0xFFFDF1E6,
            warningInk: 0xFF7A3B06
        )
        public static let dark: SpecPalette = SpecPalette(
            primary: 0xFFB9CDFF,
            onPrimary: 0xFF16294E,
            surface: 0xFF111C31,
            ink: 0xFFF4F7FE,
            muted: 0xFFB7C4DA,
            soft: 0xFF1A2942,
            border: 0xFF566983,
            accent: 0xFFFFB579,
            success: 0xFF8FE0B8,
            error: 0xFFFFB4AB,
            warningSoft: 0xFF3A2A1A,
            warningInk: 0xFFFFD3AE
        )
        public static let fontFamily: String = "Ubuntu"
        public static let fontWeightsRegular: Int = 400
        public static let fontWeightsMedium: Int = 500
        public static let fontWeightsBold: Int = 700
        public static let textAlign: String = "center"
        public static let typeTitle: SpecTextStyle = SpecTextStyle(
            size: 24.0,
            lineHeight: 30.0,
            weight: 700
        )
        public static let typeSubtitle: SpecTextStyle = SpecTextStyle(
            size: 17.0,
            lineHeight: 24.0,
            weight: 500
        )
        public static let typeBody: SpecTextStyle = SpecTextStyle(
            size: 16.0,
            lineHeight: 24.0,
            weight: 400
        )
        public static let typeButton: SpecTextStyle = SpecTextStyle(
            size: 16.0,
            lineHeight: 22.0,
            weight: 500
        )
        public static let typeLabel: SpecTextStyle = SpecTextStyle(
            size: 14.0,
            lineHeight: 20.0,
            weight: 500
        )
        public static let typeSmall: SpecTextStyle = SpecTextStyle(
            size: 13.0,
            lineHeight: 19.0,
            weight: 400
        )
        public static let typeEyebrow: SpecTextStyle = SpecTextStyle(
            size: 13.0,
            lineHeight: 18.0,
            weight: 500
        )
        public static let typeChip: SpecTextStyle = SpecTextStyle(
            size: 12.0,
            lineHeight: 16.0,
            weight: 500
        )
        public static let spacingXxs: Int = 2
        public static let spacingXs: Int = 4
        public static let spacingSm: Int = 8
        public static let spacingMd: Int = 12
        public static let spacingLg: Int = 16
        public static let spacingXl: Int = 24
        public static let spacingXxl: Int = 32
        public static let spacingGutter: Int = 24
        public static let spacingGap: Int = 16
        public static let spacingSection: Int = 10
        public static let radiusXs: Int = 3
        public static let radiusSm: Int = 6
        public static let radiusMd: Int = 10
        public static let radiusLg: Int = 14
        public static let radiusXl: Int = 16
        public static let radiusSheet: Int = 24
        public static let radiusPill: Int = 999
        public static let sizeButtonHeight: Int = 56
        public static let sizeLinkHeight: Int = 48
        public static let sizeOptionHeight: Int = 72
        public static let sizeHeaderHeight: Int = 56
        public static let sizeMaxContentWidth: Int = 600
        public static let sizeMark: Int = 30
        public static let sizeIcon: Int = 24
        public static let sizeIllustration: Int = 64
        public static let sizeIconStroke: Double = 1.75
    }

    public enum Icons {
        public static let camera: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 4 8.5 C 4 7.395 4.895 6.5 6 6.5 L 7.6 6.5 C 7.915 6.5 8.211 6.352 8.4 6.1 L 9.6 4.4 C 9.789 4.148 10.085 4 10.4 4 L 13.6 4 C 13.915 4 14.211 4.148 14.4 4.4 L 15.6 6.1 C 15.789 6.352 16.085 6.5 16.4 6.5 L 18 6.5 C 19.105 6.5 20 7.395 20 8.5 L 20 17.5 C 20 18.605 19.105 19.5 18 19.5 L 6 19.5 C 4.895 19.5 4 18.605 4 17.5 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 15.25 12.75 C 15.25 14.545 13.795 16 12 16 C 10.205 16 8.75 14.545 8.75 12.75 C 8.75 10.955 10.205 9.5 12 9.5 C 13.795 9.5 15.25 10.955 15.25 12.75 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let chevronLeft: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 14.5 6 L 8.5 12 L 14.5 18",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let chevronRight: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 9.5 6 L 15.5 12 L 9.5 18",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let document: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 14 3 L 7 3 C 5.895 3 5 3.895 5 5 L 5 19 C 5 20.105 5.895 21 7 21 L 17 21 C 18.105 21 19 20.105 19 19 L 19 8 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 14 3 L 14 7 C 14 7.552 14.448 8 15 8 L 19 8",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 9 13 L 15 13",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 9 17 L 13 17",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let error: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 21 12 C 21 16.971 16.971 21 12 21 C 7.029 21 3 16.971 3 12 C 3 7.029 7.029 3 12 3 C 16.971 3 21 7.029 21 12 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 12 7.75 L 12 12.75",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 12 16.25 L 12 16.26",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let idCard: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 5 5 L 19 5 C 20.105 5 21 5.895 21 7 L 21 17 C 21 18.105 20.105 19 19 19 L 5 19 C 3.895 19 3 18.105 3 17 L 3 7 C 3 5.895 3.895 5 5 5 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 10.25 10 C 10.25 10.966 9.466 11.75 8.5 11.75 C 7.534 11.75 6.75 10.966 6.75 10 C 6.75 9.034 7.534 8.25 8.5 8.25 C 9.466 8.25 10.25 9.034 10.25 10 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 5.75 15.5 C 6.25 14.1 7.25 13.25 8.5 13.25 C 9.75 13.25 10.75 14.1 11.25 15.5",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 14 10 L 18 10",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 14 14 L 16.5 14",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let location: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 12 21.25 C 12 21.25 5.5 15.6 5.5 10 C 5.5 6.41 8.41 3.5 12 3.5 C 15.59 3.5 18.5 6.41 18.5 10 C 18.5 15.6 12 21.25 12 21.25 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 14.25 10 C 14.25 11.243 13.243 12.25 12 12.25 C 10.757 12.25 9.75 11.243 9.75 10 C 9.75 8.757 10.757 7.75 12 7.75 C 13.243 7.75 14.25 8.757 14.25 10 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let received: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 14 3 L 7 3 C 5.895 3 5 3.895 5 5 L 5 19 C 5 20.105 5.895 21 7 21 L 17 21 C 18.105 21 19 20.105 19 19 L 19 8 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 14 3 L 14 7 C 14 7.552 14.448 8 15 8 L 19 8",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 9 14.75 L 11.25 17 L 15.25 12.5",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let receivedIllustration: SpecIcon = SpecIcon(
            viewBox: 64.0,
            strokeWidth: 2.5,
            paths: [
                SpecIconPath(
                    d: "M 62 32 C 62 48.569 48.569 62 32 62 C 15.431 62 2 48.569 2 32 C 2 15.431 15.431 2 32 2 C 48.569 2 62 15.431 62 32 Z",
                    stroke: false,
                    fill: true,
                    strokeWidth: 2.5,
                    strokeOpacity: 1.0,
                    fillOpacity: 0.08
                ),
                SpecIconPath(
                    d: "M 36 12 L 23 12 C 20.791 12 19 13.791 19 16 L 19 48 C 19 50.209 20.791 52 23 52 L 41 52 C 43.209 52 45 50.209 45 48 L 45 21 Z",
                    stroke: true,
                    fill: true,
                    strokeWidth: 2.5,
                    strokeOpacity: 1.0,
                    fillOpacity: 0.16
                ),
                SpecIconPath(
                    d: "M 36 12 L 36 18 C 36 19.657 37.343 21 39 21 L 45 21",
                    stroke: true,
                    fill: false,
                    strokeWidth: 2.5,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 25 24 L 31 24",
                    stroke: true,
                    fill: false,
                    strokeWidth: 2.5,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 25 30 L 39 30",
                    stroke: true,
                    fill: false,
                    strokeWidth: 2.5,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 25.5 39.5 L 30 44 L 38.5 34.5",
                    stroke: true,
                    fill: false,
                    strokeWidth: 3.0,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let selfie: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 4 8 L 4 6 C 4 4.895 4.895 4 6 4 L 8 4",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 16 4 L 18 4 C 19.105 4 20 4.895 20 6 L 20 8",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 20 16 L 20 18 C 20 19.105 19.105 20 18 20 L 16 20",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 8 20 L 6 20 C 4.895 20 4 19.105 4 18 L 4 16",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 15 10 C 15 11.657 13.657 13 12 13 C 10.343 13 9 11.657 9 10 C 9 8.343 10.343 7 12 7 C 13.657 7 15 8.343 15 10 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 7.5 17.5 C 8.4 15.6 10.1 14.5 12 14.5 C 13.9 14.5 15.6 15.6 16.5 17.5",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let upload: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 12 15 L 12 4",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 7.5 8.5 L 12 4 L 16.5 8.5",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 4 15 L 4 18 C 4 19.105 4.895 20 6 20 L 18 20 C 19.105 20 20 19.105 20 18 L 20 15",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let video: SpecIcon = SpecIcon(
            viewBox: 24.0,
            strokeWidth: 1.75,
            paths: [
                SpecIconPath(
                    d: "M 3 7.5 C 3 6.395 3.895 5.5 5 5.5 L 13 5.5 C 14.105 5.5 15 6.395 15 7.5 L 15 16.5 C 15 17.605 14.105 18.5 13 18.5 L 5 18.5 C 3.895 18.5 3 17.605 3 16.5 Z",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
                SpecIconPath(
                    d: "M 15 10.5 L 20.2 7.6 C 20.352 7.486 20.554 7.468 20.724 7.553 C 20.893 7.637 21 7.811 21 8 L 21 16 C 21 16.189 20.893 16.363 20.724 16.447 C 20.554 16.532 20.352 16.514 20.2 16.4 L 15 13.5",
                    stroke: true,
                    fill: false,
                    strokeWidth: 1.75,
                    strokeOpacity: 1.0,
                    fillOpacity: 1.0
                ),
            ]
        )
        public static let all: [String: SpecIcon] = [
            "camera": camera,
            "chevron_left": chevronLeft,
            "chevron_right": chevronRight,
            "document": document,
            "error": error,
            "id_card": idCard,
            "location": location,
            "received": received,
            "received_illustration": receivedIllustration,
            "selfie": selfie,
            "upload": upload,
            "video": video,
        ]
    }
}
