import XCTest
@testable import CredflareSDK

final class ClientTests: XCTestCase {
    var server: Process!
    var base: URL!
    override func setUpWithError() throws {
        server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let script = Bundle.module.url(forResource: "ContractServer", withExtension: "mjs")!
        let directory = Bundle.module.url(forResource: "capture-snapshot-or-upload", withExtension: "json", subdirectory: "Fixtures")!.deletingLastPathComponent()
        server.arguments = ["node", script.path, directory.path]
        let pipe = Pipe(); server.standardOutput = pipe
        try server.run()
        let raw = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(raw) else { throw CredflareError.invalidResponse }
        base = URL(string: "http://127.0.0.1:\(port)/api/v1")!
    }
    override func tearDown() {
        if server?.isRunning == true { server.terminate(); server.waitUntilExit() }
    }
    func descriptor(_ token: String = "test-session-token", base: URL? = nil) throws -> SessionDescriptor {
        let raw = try fixture("capture-snapshot-or-upload")
        let json = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        let data = json["data"] as! [String: Any]
        return try SessionDescriptor(sessionID: UUID(uuidString: data["session_id"] as! String)!, token: token, apiBaseURL: base ?? self.base, expiresAt: data["expires_at"] as! String)
    }
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!) }
    func testHTTPRequirementsAndCapturePlans() async throws {
        let client = VerificationSession(try descriptor())
        let info = try await client.get()
        let requirement = try XCTUnwrap(info.profile?.documentRequirements.first)
        XCTAssertEqual(try requirement.captureSteps().map(\.id), ["camera_or_upload:front", "camera_or_upload:back"])
        struct Payload: Decodable { let data: SessionInfo }
        let both = try JSONDecoder().decode(Payload.self, from: fixture("capture-snapshot_and_upload"))
        XCTAssertEqual(try both.data.profile!.documentRequirements[0].captureSteps().map(\.id), ["camera:front", "camera:back", "upload:front", "upload:back"])
    }
    func testUploadsCarrySourceAndStableKeyOverHTTP() async throws {
        let client = VerificationSession(try descriptor())
        let key = UUID()
        let bytes = try Data(contentsOf: Bundle.module.url(forResource: "sample-front", withExtension: "png", subdirectory: "Fixtures")!)
        let file = try await client.upload(bytes, filename: "sample-front.png", source: .upload, side: .front, documentTypeID: 1, key: key)
        XCTAssertEqual(file.id, 1)
        let stats = try await stats()
        XCTAssertEqual(stats["uploadSource"] as? String, "upload")
        XCTAssertEqual(stats["requestKey"] as? String, key.uuidString.lowercased())
        try await client.cancel()
    }
    func testHTTPAuthenticationError() async throws {
        do { _ = try await VerificationSession(try descriptor("unauthorized")).get(); XCTFail("Expected authentication failure") }
        catch let error as CredflareError { XCTAssertEqual(error.type, "session_unavailable") }
    }
    func testTimeoutAndInterruptedBodyAreNetworkFailures() async throws {
        for token in ["slow", "broken-body"] {
            do { _ = try await VerificationSession(try descriptor(token), timeout: 0.2).get(); XCTFail("Expected network failure") }
            catch let error as CredflareError { XCTAssertEqual(error.type, "network") }
        }
    }
    func testRedirectDoesNotForwardCredentials() async throws {
        do { _ = try await VerificationSession(try descriptor("redirect")).get(); XCTFail("Expected redirect rejection") }
        catch let error as CredflareError { XCTAssertEqual(error.type, "api") }
        let stats = try await stats()
        XCTAssertEqual(stats["redirectHits"] as? Int, 0)
    }
    func testDescriptorRejectsUnsafeURLsAndRedactsToken() throws {
        XCTAssertThrowsError(try descriptor(base: URL(string: "http://example.test")!))
        XCTAssertThrowsError(try descriptor(base: URL(string: "https://user:password@example.test")!))
        XCTAssertFalse(String(describing: try descriptor()).contains("test-session-token"))
        XCTAssertFalse(String(reflecting: try descriptor()).contains("test-session-token"))
    }
    func stats() async throws -> [String: Any] {
        let (raw, _) = try await URLSession.shared.data(from: base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("stats"))
        return try JSONSerialization.jsonObject(with: raw) as! [String: Any]
    }
    func requests(_ suffix: String) async throws -> [[String: Any]] {
        (try await stats()["requests"] as! [[String: Any]]).filter { ($0["path"] as! String).hasSuffix(suffix) }
    }
    func json(_ request: [String: Any]) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: (request["body"] as! String).data(using: .utf8)!) as! [String: Any]
    }
    func testRequirementSettingsParseFacialAndLocationWithPlaceLabelsOnly() async throws {
        let info = try await VerificationSession(try descriptor("capture")).get()
        let requirements = try XCTUnwrap(info.profile?.requirements)
        XCTAssertEqual(requirements.map(\.type), ["facial_verification", "location_verification"])
        let facial = try XCTUnwrap(requirements[0].facial)
        XCTAssertEqual(facial.gestures, ["blink", "smile", "turn_left", "turn_right", "nod"])
        XCTAssertEqual(facial.gestureCount, 3)
        XCTAssertTrue(facial.recordVideo)
        let location = try XCTUnwrap(requirements[1].location)
        XCTAssertEqual(location.maxAccuracyM, 50)
        XCTAssertEqual(location.maxAgeS, 60)
        XCTAssertEqual(location.mockLocation, "reject")
        XCTAssertEqual(location.reference?.rule, .within)
        XCTAssertEqual(location.reference?.placeLabels, ["Head office"])
        XCTAssertFalse(info.profile!.needsHostSteps)
        XCTAssertTrue(info.profile!.requiresSelfie)
        XCTAssertTrue(info.profile!.requiresLocation)
    }
    func testRequirementsWithoutSettingsUseSpecDefaults() async throws {
        let info = try await VerificationSession(try descriptor("selfie")).get()
        let facial = try XCTUnwrap(info.profile?.requirements.first?.facial)
        XCTAssertEqual(facial.gestures, CredflareSpec.Settings.facialVerificationGesturesDefault)
        XCTAssertEqual(facial.gestureCount, CredflareSpec.Settings.facialVerificationGestureCountDefault)
        XCTAssertFalse(info.profile!.needsHostSteps)
    }
    func testLivenessChallengeUploadsAndFacialSubmissionOverHTTP() async throws {
        let client = VerificationSession(try descriptor("capture"))
        let challenge = try await client.createLivenessChallenge()
        XCTAssertEqual(challenge.challengeID, "01a1fb33-a1ee-71b2-bba9-9f484aa3bb1b")
        XCTAssertEqual(challenge.gestures, ["blink", "smile", "turn_right"])
        XCTAssertTrue(challenge.recordVideo)
        XCTAssertEqual(challenge.maxVideoSeconds, 8)
        XCTAssertNotNil(challenge.expiryDate)
        let frame = try Data(contentsOf: Bundle.module.url(forResource: "sample-front", withExtension: "png", subdirectory: "Fixtures")!)
        var keys: [UUID] = []
        var gestureIDs: [Int] = []
        for gesture in challenge.gestures {
            let key = UUID(); keys.append(key)
            gestureIDs.append(try await client.uploadBiometric(frame, filename: "\(gesture).png", type: .gesture, challengeID: challenge.challengeID, gesture: gesture, key: key).id)
        }
        let videoKey = UUID(), selfieKey = UUID(), submitKey = UUID()
        let video = try await client.uploadBiometric(Data(repeating: 0, count: 64), filename: "liveness.mp4", type: .livenessVideo, challengeID: challenge.challengeID, key: videoKey)
        let selfie = try await client.uploadBiometric(frame, filename: "selfie.png", type: .selfie, challengeID: challenge.challengeID, key: selfieKey)
        XCTAssertEqual(gestureIDs, [3, 3, 3])
        XCTAssertEqual(video.id, 5)
        XCTAssertEqual(selfie.id, 4)
        let results = challenge.gestures.map { LivenessResult(challenge: $0, completed: true, timestamp: "2026-11-20T23:04:00.000Z") }
        let id = try await client.submitFacial(FacialSubmission(challengeID: challenge.challengeID, imageFileID: selfie.id, gestureFileIDs: gestureIDs, videoFileID: video.id, provider: "vision", livenessResults: results, faceDetection: FaceDetectionSummary(detected: true, faceCount: 1, isCentered: true, isCorrectSize: true), capturedAt: "2026-11-20T23:04:01.000Z"), key: submitKey)
        XCTAssertEqual(id, 1)

        let challenges = try await requests("/liveness-challenges")
        XCTAssertEqual(challenges.first?["method"] as? String, "POST")
        let uploads = try await requests("/uploads/biometrics")
        XCTAssertEqual(uploads.count, 5)
        for (index, gesture) in challenge.gestures.enumerated() {
            let body = uploads[index]["body"] as! String
            XCTAssertTrue(body.contains("name=\"type\"\r\n\r\ngesture\r\n"))
            XCTAssertTrue(body.contains("name=\"gesture\"\r\n\r\n\(gesture)\r\n"))
            XCTAssertTrue(body.contains("name=\"challenge_id\"\r\n\r\n\(challenge.challengeID)\r\n"))
            XCTAssertTrue(body.contains("name=\"capture_source\"\r\n\r\ncamera\r\n"))
            XCTAssertEqual(uploads[index]["key"] as? String, keys[index].uuidString.lowercased())
        }
        let videoBody = uploads[3]["body"] as! String
        XCTAssertTrue(videoBody.contains("name=\"type\"\r\n\r\nliveness_video\r\n"))
        XCTAssertTrue(videoBody.contains("Content-Type: video/mp4"))
        XCTAssertFalse(videoBody.contains("name=\"gesture\""))
        XCTAssertEqual(uploads[3]["key"] as? String, videoKey.uuidString.lowercased())
        let selfieBody = uploads[4]["body"] as! String
        XCTAssertTrue(selfieBody.contains("name=\"type\"\r\n\r\nselfie\r\n"))
        XCTAssertTrue(selfieBody.contains("name=\"capture_source\"\r\n\r\ncamera\r\n"))
        XCTAssertFalse(selfieBody.contains("document_type_id"))

        let submits = try await requests("/submit")
        let submit = try XCTUnwrap(submits.first)
        XCTAssertEqual(submit["key"] as? String, submitKey.uuidString.lowercased())
        let body = try json(submit)
        XCTAssertEqual(body["type"] as? String, "facial_verification")
        XCTAssertEqual(body["challenge_id"] as? String, challenge.challengeID)
        XCTAssertEqual(body["image_file_id"] as? Int, 4)
        XCTAssertEqual(body["gesture_file_ids"] as? [Int], [3, 3, 3])
        XCTAssertEqual(body["video_file_id"] as? Int, 5)
        let metadata = body["metadata"] as! [String: Any]
        XCTAssertEqual(metadata["provider"] as? String, "vision")
        XCTAssertEqual((metadata["liveness_results"] as! [[String: Any]]).map { $0["challenge"] as! String }, challenge.gestures)
        XCTAssertEqual((metadata["face_detection"] as! [String: Any])["face_count"] as? Int, 1)
        XCTAssertEqual(metadata["captured_at"] as? String, "2026-11-20T23:04:01.000Z")
    }
    func testBiometricUploadRejectsMismatchedGestureAndFormat() async throws {
        let client = VerificationSession(try descriptor("capture"))
        for (type, gesture, name) in [(BiometricUploadType.gesture, nil as String?, "a.jpg"), (.selfie, "smile", "a.jpg"), (.livenessVideo, nil, "a.jpg"), (.selfie, nil, "a.mp4")] {
            do { _ = try await client.uploadBiometric(Data([1]), filename: name, type: type, challengeID: "c", gesture: gesture, key: UUID()); XCTFail("Expected validation error") }
            catch let error as CredflareError { XCTAssertEqual(error.type, "validation") }
        }
        let none = try await requests("/uploads/biometrics")
        XCTAssertTrue(none.isEmpty)
    }
    func location(mock: Bool?) -> LocationSubmission {
        LocationSubmission(latitude: 4.0511, longitude: 9.7679, accuracy: 12.5, altitude: nil, fixTime: Date(timeIntervalSince1970: 1_795_000_000), isMock: mock, provider: "gps", capturedAt: Date(timeIntervalSince1970: 1_795_000_002))
    }
    func testLocationSubmissionOverHTTP() async throws {
        let key = UUID()
        let id = try await VerificationSession(try descriptor("capture")).submitLocation(location(mock: nil), key: key)
        XCTAssertEqual(id, 2)
        let submits = try await requests("/submit")
        let submit = try XCTUnwrap(submits.first)
        XCTAssertEqual(submit["key"] as? String, key.uuidString.lowercased())
        let body = try json(submit)
        XCTAssertEqual(body["type"] as? String, "location_verification")
        XCTAssertEqual(body["latitude"] as? Double, 4.0511)
        XCTAssertEqual(body["longitude"] as? Double, 9.7679)
        let metadata = body["metadata"] as! [String: Any]
        XCTAssertEqual(metadata["accuracy"] as? Double, 12.5)
        XCTAssertTrue(metadata["altitude"] is NSNull)
        XCTAssertTrue(metadata["is_mock"] is NSNull)
        XCTAssertEqual(metadata["provider"] as? String, "gps")
        XCTAssertEqual(metadata["fix_time"] as? String, "2026-11-18T11:06:40.000Z")
        XCTAssertEqual(metadata["captured_at"] as? String, "2026-11-18T11:06:42.000Z")
        XCTAssertNil(body["place"])
    }
    func testLocationRejectionSurfacesServerReason() async throws {
        for (token, name) in [("location-reject", "location-rejection"), ("reference-reject", "reference-rejection")] {
            let expected = (try JSONSerialization.jsonObject(with: fixture(name)) as! [String: Any])["message"] as! String
            do { _ = try await VerificationSession(try descriptor(token)).submitLocation(location(mock: false), key: UUID()); XCTFail("Expected rejection") }
            catch let error as CredflareError {
                guard case .api(let status, let message) = error else { return XCTFail("Unexpected \(error)") }
                XCTAssertEqual(status, 422)
                XCTAssertEqual(message, expected)
                XCTAssertEqual(error.type, "validation")
                XCTAssertEqual(error.localizedDescription, expected)
            }
        }
    }
    func testFakeProviderLivenessRunUploadsEvidenceAndSubmits() async throws {
        let client = VerificationSession(try descriptor("capture"))
        let issued = try await client.createLivenessChallenge()
        let capture = try LivenessCapture(challenge: issued, provider: FakeFaceSignalProvider(script: passingScript), clock: { ISO8601.parse("2026-11-20T23:04:00Z")! })
        let buffer = pixelBuffer()
        for index in passingScript.indices { _ = capture.process(buffer, seconds: Double(index) * 0.066) }
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 1, count: 128).write(to: video)
        defer { try? FileManager.default.removeItem(at: video) }
        let evidence = try XCTUnwrap(capture.evidence(video: video))
        var keys: [String: UUID] = [:]
        let id = try await LivenessSubmitter.submit(evidence, client: client, keys: &keys)
        XCTAssertEqual(id, 1)
        XCTAssertEqual(Set(keys.keys), ["gesture-0", "gesture-1", "gesture-2", "video", "selfie", "submit"])
        let uploads = try await requests("/uploads/biometrics")
        XCTAssertEqual(uploads.map { ($0["body"] as! String).contains("Content-Type: image/jpeg") }, [true, true, true, false, true])
        let submits = try await requests("/submit")
        let body = try json(try XCTUnwrap(submits.first))
        XCTAssertEqual(body["gesture_file_ids"] as? [Int], [3, 3, 3])
        XCTAssertEqual(body["video_file_id"] as? Int, 5)
        XCTAssertEqual(body["image_file_id"] as? Int, 4)
        let metadata = body["metadata"] as! [String: Any]
        XCTAssertEqual((metadata["liveness_results"] as! [[String: Any]]).map { $0["challenge"] as! String }, issued.gestures)
        XCTAssertEqual((metadata["liveness_results"] as! [[String: Any]]).map { $0["completed"] as! Bool }, [true, true, true])
    }
}
