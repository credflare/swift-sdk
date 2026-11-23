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
        let issued = (try JSONSerialization.jsonObject(with: fixture("liveness-challenge")) as! [String: Any])["data"] as! [String: Any]
        XCTAssertEqual(challenge.challengeID, issued["challenge_id"] as? String)
        XCTAssertEqual(challenge.gestures, issued["gestures"] as? [String])
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
        try await assertEveryWriteHasAKey()
    }
    func assertEveryWriteHasAKey() async throws {
        let writes = (try await stats()["requests"] as! [[String: Any]]).filter { ($0["path"] as! String).contains("/uploads/") || ($0["path"] as! String).hasSuffix("/submit") }
        XCTAssertFalse(writes.isEmpty)
        for write in writes { XCTAssertNotNil(UUID(uuidString: write["key"] as? String ?? ""), write["path"] as! String) }
        XCTAssertEqual(Set(writes.map { $0["key"] as! String }).count, writes.count)
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
        try await assertEveryWriteHasAKey()
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
    func testLocationRejectionCarriesTheSpecCode() async throws {
        let info = try await VerificationSession(try descriptor("capture")).get()
        let headOffice = try XCTUnwrap(info.profile?.requirements.compactMap(\.location).first?.reference)
        for (token, name, code, copy) in [
            ("location-reject", "location-rejection", RejectionCode.locationAccuracy, CredflareCopy.text(CredflareSpec.CopyKey.locationPlaceNotPrecise)),
            ("reference-reject", "reference-rejection", RejectionCode.locationReferenceNotMatched, "You do not seem to be at Head office yet. Move closer, then try again."),
        ] {
            let expected = (try JSONSerialization.jsonObject(with: fixture(name)) as! [String: Any])["message"] as! String
            do { _ = try await VerificationSession(try descriptor(token)).submitLocation(location(mock: false), key: UUID()); XCTFail("Expected rejection") }
            catch let error as CredflareError {
                guard case .api(let status, let message, let parsed) = error else { return XCTFail("Unexpected \(error)") }
                XCTAssertEqual(status, 422)
                XCTAssertEqual(message, expected)
                XCTAssertEqual(parsed, code)
                XCTAssertTrue(parsed?.isKnown ?? false)
                XCTAssertEqual(error.type, "validation")
                XCTAssertEqual(Rejection(error, requester: nil, reference: headOffice).message, copy)
            }
        }
    }
    func testContractServerRefusesWritesWithoutAKey() async throws {
        var request = URLRequest(url: base.appendingPathComponent("sdk/sessions/\(try descriptor().sessionID.uuidString.lowercased())/submit"))
        request.httpMethod = "POST"
        request.setValue("Bearer capture", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"type":"location_verification"}"#.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 422)
    }
    func testFakeProviderLivenessRunUploadsEvidenceAndSubmits() async throws {
        let client = VerificationSession(try descriptor("capture"))
        let issued = try await client.createLivenessChallenge()
        let script = scriptPassing(issued.gestures)
        let capture = try LivenessCapture(challenge: issued, provider: FakeFaceSignalProvider(script: script), clock: { issued.expiryDate!.addingTimeInterval(-60) })
        let buffer = pixelBuffer()
        for index in script.indices { _ = capture.process(buffer, seconds: Double(index) * 0.066) }
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
        try await assertEveryWriteHasAKey()
    }
    func testDroppedLivenessSubmitRetriesWithTheSameKeysAndANewChallengeGetsNewKeys() async throws {
        let client = VerificationSession(try descriptor("drop-submit"))
        func evidence() async throws -> LivenessEvidence {
            let issued = try await client.createLivenessChallenge()
            let script = scriptPassing(issued.gestures)
            let capture = try LivenessCapture(challenge: issued, provider: FakeFaceSignalProvider(script: script), clock: { issued.expiryDate!.addingTimeInterval(-60) })
            let buffer = pixelBuffer()
            for index in script.indices { _ = capture.process(buffer, seconds: Double(index) * 0.066) }
            let video = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            try Data(repeating: 1, count: 128).write(to: video)
            addTeardownBlock { try? FileManager.default.removeItem(at: video) }
            return try XCTUnwrap(capture.evidence(video: video))
        }
        func writeKeys() async throws -> [String] {
            (try await stats()["requests"] as! [[String: Any]]).filter { ($0["path"] as! String).contains("/uploads/") || ($0["path"] as! String).hasSuffix("/submit") }.map { $0["key"] as! String }
        }
        let first = try await evidence()
        var keys: [String: UUID] = [:]
        do { _ = try await LivenessSubmitter.submit(first, client: client, keys: &keys); XCTFail("The first submit was not dropped") } catch {}
        let dropped = try await writeKeys()
        XCTAssertEqual(dropped.count, 6)
        XCTAssertEqual(dropped.last, keys["submit"]?.uuidString.lowercased())
        let id = try await LivenessSubmitter.submit(first, client: client, keys: &keys)
        XCTAssertEqual(id, 1)
        let retried = Array(try await writeKeys().dropFirst(dropped.count))
        XCTAssertEqual(retried, dropped)
        var fresh: [String: UUID] = [:]
        _ = try await LivenessSubmitter.submit(try await evidence(), client: client, keys: &fresh)
        let next = Array(try await writeKeys().dropFirst(dropped.count + retried.count))
        XCTAssertEqual(next.count, 6)
        XCTAssertTrue(Set(next).isDisjoint(with: dropped))
    }
    func testDocumentsListNamesOnlyTheStepsThatFollow() throws {
        struct Payload: Decodable { let data: SessionInfo }
        func profile(_ name: String) throws -> SessionInfo.Profile { try XCTUnwrap(JSONDecoder().decode(Payload.self, from: fixture(name)).data.profile) }
        XCTAssertEqual(try profile("combined-session").nextStepsCopyKey, CredflareSpec.CopyKey.documentsSelfieNext)
        XCTAssertEqual(try profile("session").nextStepsCopyKey, CredflareSpec.CopyKey.documentsHostStepsNext)
        XCTAssertEqual(try profile("capture-session").stepsAfterDocuments, ["facial_verification", "location_verification"])
        XCTAssertEqual(try profile("capture-session").nextStepsCopyKey, CredflareSpec.CopyKey.documentsSelfieLocationNext)
    }
    func testEveryCaptureRejectionShowsItsSpecScreen() async throws {
        let headOffice = try XCTUnwrap(PlaceReference(try JSONDecoder().decode(JSONValue.self, from: Data(#"{"rule":"within","match":"any","places":[{"label":"Head office"}]}"#.utf8))))
        let directory = Bundle.module.url(forResource: "rejections", withExtension: nil, subdirectory: "Fixtures")!
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertEqual(Set(files.map { $0.deletingPathExtension().lastPathComponent }), Set(CredflareSpec.ErrorCode.meanings.keys))
        XCTAssertEqual(Set(CredflareSpec.Rejection.codes.keys), Set(CredflareSpec.ErrorCode.meanings.keys))
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("location.") || name.hasPrefix("liveness.") else { continue }
            let client = VerificationSession(try descriptor("reject:\(name)"))
            do {
                if name.hasPrefix("location.") { _ = try await client.submitLocation(location(mock: false), key: UUID()) }
                else { _ = try await client.submitFacial(FacialSubmission(challengeID: "01a1fb8d-6c01-7160-a4fe-31853bb8dbdd", imageFileID: 4, gestureFileIDs: [3], videoFileID: 5, provider: "vision", livenessResults: [], faceDetection: FaceDetectionSummary(detected: true, faceCount: 1, isCentered: true, isCorrectSize: true), capturedAt: "2026-11-21T00:43:00.000Z"), key: UUID()) }
                XCTFail("\(name) was not rejected")
            } catch let error as CredflareError {
                XCTAssertEqual(error.code?.rawValue, name)
                XCTAssertTrue(error.code?.isKnown ?? false, name)
                XCTAssertEqual(error.type, "validation", name)
                let entry = try XCTUnwrap(CredflareSpec.Rejection.codes[name])
                let screen = Rejection(error, requester: "Acme Bank")
                XCTAssertEqual(screen.title, CredflareCopy.text(entry.title), name)
                XCTAssertEqual(screen.message, CredflareCopy.text(entry.message, ["verifier": "Acme Bank"]), name)
                XCTAssertEqual(screen.action, name.hasPrefix("location.") ? .retry : .restart, name)
                XCTAssertEqual(screen.requestedBy, "Requested by Acme Bank.", name)
                if name.hasPrefix("liveness.") {
                    XCTAssertTrue(LivenessRejection.needsNewChallenge(error), name)
                    XCTAssertEqual(screen.actionLabel, "Start again", name)
                } else {
                    XCTAssertEqual(screen.actionLabel, "Try again", name)
                }
            }
        }
        XCTAssertFalse(LivenessRejection.needsNewChallenge(.network("offline")))
        let rejected = CredflareError.api(422, "", code: .locationReferenceNotMatched)
        XCTAssertEqual(Rejection(rejected, requester: nil, reference: headOffice).message, "You do not seem to be at Head office yet. Move closer, then try again.")
        let depot = try XCTUnwrap(PlaceReference(try JSONDecoder().decode(JSONValue.self, from: Data(#"{"rule":"outside","places":[{"label":"Depot"}]}"#.utf8))))
        XCTAssertEqual(Rejection(rejected, requester: nil, reference: depot).message, "You seem to be too close to Depot. Move away, then try again.")
        XCTAssertEqual(Rejection(rejected, requester: "Acme Bank").message, "Your location does not match the place requested by Acme Bank. Try again from the right place.")
        let accuracy = CredflareError.api(422, "", code: .locationAccuracy)
        XCTAssertEqual(Rejection(accuracy, requester: nil, reference: headOffice).message, CredflareCopy.text(CredflareSpec.CopyKey.locationPlaceNotPrecise))
        XCTAssertEqual(Rejection(accuracy, requester: nil).message, CredflareCopy.text(CredflareSpec.CopyKey.locationLowAccuracy))
        XCTAssertEqual(Rejection(.api(422, "", code: .livenessChallengeExpired), requester: nil).message, CredflareCopy.text(CredflareSpec.CopyKey.livenessExpired))
        XCTAssertEqual(Rejection(.api(422, "", code: .livenessChallengeExpired), requester: nil).title, "Time ran out")
    }
}
