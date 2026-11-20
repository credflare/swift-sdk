import Foundation
import CoreLocation

public struct LocationFix: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let accuracy: Double
    public let altitude: Double?
    public let timestamp: Date
    public let isMock: Bool?
    public init(latitude: Double, longitude: Double, accuracy: Double, altitude: Double?, timestamp: Date, isMock: Bool?) {
        self.latitude = latitude; self.longitude = longitude; self.accuracy = accuracy; self.altitude = altitude; self.timestamp = timestamp; self.isMock = isMock
    }

    public init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        accuracy = location.horizontalAccuracy
        altitude = location.verticalAccuracy > 0 ? location.altitude : nil
        timestamp = location.timestamp
        isMock = location.sourceInformation?.isSimulatedBySoftware
    }

    public func submission(provider: String = "gps", capturedAt: Date = Date()) -> LocationSubmission {
        LocationSubmission(latitude: latitude, longitude: longitude, accuracy: accuracy, altitude: altitude, fixTime: timestamp, isMock: isMock, provider: provider, capturedAt: capturedAt)
    }
}

public enum LocationFixVerdict: Equatable, Sendable { case accepted, lowAccuracy, stale, mock }

public extension LocationSettings {
    func evaluate(_ fix: LocationFix, now: Date) -> LocationFixVerdict {
        if fix.isMock == true && mockLocation == "reject" { return .mock }
        guard fix.accuracy >= 0, fix.accuracy <= Double(maxAccuracyM) else { return .lowAccuracy }
        guard now.timeIntervalSince(fix.timestamp) <= Double(maxAgeS) else { return .stale }
        return .accepted
    }
}

public enum LocationCopy {
    public static func title(_ reference: PlaceReference?) -> String {
        guard let reference, reference.placeLabels.count == 1 else { return CredflareCopy.text(CredflareSpec.CopyKey.locationTitle) }
        let key = reference.rule == .within ? CredflareSpec.CopyKey.locationPlaceTitleWithin : CredflareSpec.CopyKey.locationPlaceTitleOutside
        return CredflareCopy.text(key, ["place": reference.placeLabels[0]])
    }

    public static func requirement(_ reference: PlaceReference?) -> String? {
        guard let reference, let first = reference.placeLabels.first else { return nil }
        let places = reference.placeLabels.joined(separator: ", ")
        switch (reference.rule, reference.placeLabels.count) {
        case (.within, 1): return CredflareCopy.text(CredflareSpec.CopyKey.locationPlaceNeedWithin, ["place": first])
        case (.within, _): return CredflareCopy.text(reference.match == "all" ? CredflareSpec.CopyKey.locationPlaceNeedWithinAll : CredflareSpec.CopyKey.locationPlaceNeedWithinAny, ["places": places])
        case (.outside, 1): return CredflareCopy.text(CredflareSpec.CopyKey.locationPlaceNeedOutside, ["place": first])
        case (.outside, _): return CredflareCopy.text(CredflareSpec.CopyKey.locationPlaceNeedOutsideAll, ["places": places])
        }
    }
}

public enum LocationAuthorization: Sendable { case granted, denied, unavailable }

public protocol LocationSource: AnyObject {
    func authorize() async -> LocationAuthorization
    func fixes() -> AsyncStream<LocationFix>
    func stop()
}

public enum LocationOutcome: Equatable, Sendable {
    case fix(LocationFix)
    case denied, unavailable, timeout, lowAccuracy, mock
}

public enum LocationCollector {
    public static func collect(from source: LocationSource, settings: LocationSettings, timeout: TimeInterval = TimeInterval(CredflareSpec.Location.fixTimeoutS), now: @escaping @Sendable () -> Date = Date.init, onFix: (@Sendable (LocationFix) -> Void)? = nil) async -> LocationOutcome {
        switch await source.authorize() {
        case .denied: return .denied
        case .unavailable: return .unavailable
        case .granted: break
        }
        let stream = source.fixes()
        defer { source.stop() }
        return await withTaskGroup(of: LocationOutcome?.self) { group in
            group.addTask {
                var worst: LocationOutcome = .timeout
                for await fix in stream {
                    onFix?(fix)
                    switch settings.evaluate(fix, now: now()) {
                    case .accepted: return .fix(fix)
                    case .mock: worst = .mock
                    case .lowAccuracy, .stale: if worst != .mock { worst = .lowAccuracy }
                    }
                }
                return worst == .timeout ? .unavailable : worst
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if let first { return first }
            return .timeout
        }
    }
}

public final class DeviceLocationSource: NSObject, LocationSource, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var authorization: CheckedContinuation<LocationAuthorization, Never>?
    private var continuation: AsyncStream<LocationFix>.Continuation?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization? {
        switch status {
        case .notDetermined: return nil
        case .denied, .restricted: return .denied
        default: return .granted
        }
    }

    @MainActor public func authorize() async -> LocationAuthorization {
        if let known = Self.map(manager.authorizationStatus) { return known }
        return await withCheckedContinuation { continuation in
            authorization = continuation
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestAlwaysAuthorization()
            #endif
        }
    }

    public func fixes() -> AsyncStream<LocationFix> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in DispatchQueue.main.async { self?.manager.stopUpdatingLocation() } }
            DispatchQueue.main.async { self.manager.startUpdatingLocation() }
        }
    }

    public func stop() {
        continuation?.finish(); continuation = nil
        DispatchQueue.main.async { self.manager.stopUpdatingLocation() }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let result = Self.map(manager.authorizationStatus), let pending = authorization else { return }
        authorization = nil
        pending.resume(returning: result)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 { continuation?.yield(LocationFix(location)) }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { continuation?.finish(); continuation = nil }
    }
}
