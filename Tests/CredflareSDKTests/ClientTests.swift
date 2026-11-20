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
        let (raw, _) = try await URLSession.shared.data(from: base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("stats"))
        let stats = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
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
        let (raw, _) = try await URLSession.shared.data(from: base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("stats"))
        let stats = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        XCTAssertEqual(stats["redirectHits"] as? Int, 0)
    }
    func testDescriptorRejectsUnsafeURLsAndRedactsToken() throws {
        XCTAssertThrowsError(try descriptor(base: URL(string: "http://example.test")!))
        XCTAssertThrowsError(try descriptor(base: URL(string: "https://user:password@example.test")!))
        XCTAssertFalse(String(describing: try descriptor()).contains("test-session-token"))
        XCTAssertFalse(String(reflecting: try descriptor()).contains("test-session-token"))
    }
    func testConfiguredSelfieUsesBiometricHTTPContract() async throws {
        let client = VerificationSession(try descriptor("selfie"))
        let info = try await client.get()
        XCTAssertTrue(info.profile!.requiresSelfie)
        XCTAssertFalse(info.profile!.needsHostSteps)
        XCTAssertTrue(info.profile!.documentRequirements.isEmpty)
        let key = UUID()
        let bytes = try Data(contentsOf: Bundle.module.url(forResource: "sample-front", withExtension: "png", subdirectory: "Fixtures")!)
        let file = try await client.uploadSelfie(bytes, filename: "selfie.png", key: key)
        _ = try await client.submitSelfie(imageFileID: file.id, key: UUID())
        let (raw, _) = try await URLSession.shared.data(from: base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("stats"))
        let stats = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        XCTAssertTrue((stats["selfieUpload"] as! String).contains("name=\"capture_source\"\r\n\r\ncamera"))
        XCTAssertFalse((stats["selfieUpload"] as! String).contains("document_type_id"))
        XCTAssertEqual(stats["selfieKey"] as? String, key.uuidString.lowercased())
        let body = try JSONSerialization.jsonObject(with: (stats["selfieBody"] as! String).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(body["type"] as? String, "facial_verification")
        XCTAssertEqual(body["image_file_id"] as? Int, file.id)
    }

}
