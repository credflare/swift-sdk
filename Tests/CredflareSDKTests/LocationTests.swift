import XCTest
@testable import CredflareSDK

final class FakeLocationSource: LocationSource, @unchecked Sendable {
    let authorization: LocationAuthorization
    let script: [LocationFix]
    let finishAfterScript: Bool
    private(set) var stopped = false
    init(_ authorization: LocationAuthorization = .granted, script: [LocationFix], finishAfterScript: Bool = false) { self.authorization = authorization; self.script = script; self.finishAfterScript = finishAfterScript }
    func authorize() async -> LocationAuthorization { authorization }
    func fixes() -> AsyncStream<LocationFix> {
        AsyncStream { continuation in
            for fix in script { continuation.yield(fix) }
            if finishAfterScript { continuation.finish() }
        }
    }
    func stop() { stopped = true }
}

final class LocationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    func fix(accuracy: Double, age: TimeInterval = 1, mock: Bool? = nil) -> LocationFix {
        LocationFix(latitude: 4.05, longitude: 9.76, accuracy: accuracy, altitude: nil, timestamp: now.addingTimeInterval(-age), isMock: mock)
    }
    func settings(_ fixture: String = "capture-session") throws -> LocationSettings {
        struct Payload: Decodable { let data: SessionInfo }
        let data = try Data(contentsOf: Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")!)
        return try XCTUnwrap(JSONDecoder().decode(Payload.self, from: data).data.profile?.requirements.compactMap(\.location).first)
    }

    func testFixesAreJudgedAgainstAccuracyAgeAndMockSettings() throws {
        let location = try settings()
        XCTAssertEqual(location.evaluate(fix(accuracy: 12), now: now), .accepted)
        XCTAssertEqual(location.evaluate(fix(accuracy: 50), now: now), .accepted)
        XCTAssertEqual(location.evaluate(fix(accuracy: 51), now: now), .lowAccuracy)
        XCTAssertEqual(location.evaluate(fix(accuracy: 12, age: 61), now: now), .stale)
        XCTAssertEqual(location.evaluate(fix(accuracy: 12, mock: true), now: now), .mock)
        XCTAssertEqual(location.evaluate(fix(accuracy: 12, mock: nil), now: now), .accepted)
    }

    func testCollectorKeepsListeningUntilAFixIsAccurateEnough() async throws {
        let source = FakeLocationSource(script: [fix(accuracy: 400), fix(accuracy: 80), fix(accuracy: 20)])
        let now = self.now
        let outcome = await LocationCollector.collect(from: source, settings: try settings(), timeout: 2, now: { now })
        XCTAssertEqual(outcome, .fix(fix(accuracy: 20)))
        XCTAssertTrue(source.stopped)
    }

    func testCollectorReportsDeniedTimeoutLowAccuracyAndMock() async throws {
        let location = try settings()
        let now = self.now
        var outcome = await LocationCollector.collect(from: FakeLocationSource(.denied, script: []), settings: location, timeout: 1, now: { now })
        XCTAssertEqual(outcome, .denied)
        outcome = await LocationCollector.collect(from: FakeLocationSource(script: []), settings: location, timeout: 0.2, now: { now })
        XCTAssertEqual(outcome, .timeout)
        outcome = await LocationCollector.collect(from: FakeLocationSource(script: [fix(accuracy: 300)], finishAfterScript: true), settings: location, timeout: 1, now: { now })
        XCTAssertEqual(outcome, .lowAccuracy)
        outcome = await LocationCollector.collect(from: FakeLocationSource(script: [fix(accuracy: 5, mock: true)], finishAfterScript: true), settings: location, timeout: 1, now: { now })
        XCTAssertEqual(outcome, .mock)
    }

    func testSubmissionCarriesTheFixWithoutPlaceData() throws {
        let submission = fix(accuracy: 12.5, mock: false).submission(capturedAt: now)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(submission)) as! [String: Any]
        XCTAssertEqual(Set(body.keys), ["type", "latitude", "longitude", "metadata"])
        let metadata = body["metadata"] as! [String: Any]
        XCTAssertEqual(Set(metadata.keys), ["accuracy", "altitude", "fix_time", "is_mock", "provider", "captured_at"])
        XCTAssertEqual(metadata["is_mock"] as? Bool, false)
        XCTAssertEqual(metadata["provider"] as? String, "gps")
    }

    func testPlaceCopyUsesLabelsOnly() throws {
        let headOffice = try XCTUnwrap(try settings().reference)
        XCTAssertEqual(LocationCopy.title(headOffice), "Share your location at Head office")
        XCTAssertEqual(LocationCopy.requirement(headOffice), "You need to be at Head office.")
        XCTAssertEqual(LocationCopy.title(nil), "Share your location")
        XCTAssertNil(LocationCopy.requirement(nil))
        func reference(_ json: String) throws -> PlaceReference {
            try XCTUnwrap(PlaceReference(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
        }
        let outside = try reference(#"{"rule":"outside","places":[{"label":"Depot"},{"label":"Yard"}]}"#)
        XCTAssertEqual(LocationCopy.title(outside), "Share your location")
        XCTAssertEqual(LocationCopy.requirement(outside), "You need to be away from these places: Depot, Yard.")
        let all = try reference(#"{"rule":"within","match":"all","places":[{"label":"Depot"},{"label":"Yard"}]}"#)
        XCTAssertEqual(LocationCopy.requirement(all), "You need to be at each of these places: Depot, Yard.")
        let any = try reference(#"{"rule":"within","places":[{"label":"Depot"},{"label":"Yard"}]}"#)
        XCTAssertEqual(LocationCopy.requirement(any), "You need to be at one of these places: Depot, Yard.")
        XCTAssertEqual(LocationCopy.title(try reference(#"{"rule":"outside","places":[{"label":"Depot"}]}"#)), "Share your location away from Depot")
    }
}
