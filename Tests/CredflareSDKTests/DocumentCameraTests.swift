import XCTest
@testable import CredflareSDK

final class DocumentCameraTests: XCTestCase {
    func testPickerWithoutCaptureDeviceShowsCameraUnavailable() {
        let key = DocumentCamera.blockingCopyKey(pickerAvailable: true, hasCaptureDevice: false, permissionDenied: false)
        XCTAssertEqual(key, CredflareSpec.CopyKey.errorsCameraUnavailable)
        XCTAssertEqual(CredflareCopy.text(key!), "The camera is unavailable. Try again on a device with a camera.")
    }

    func testNoPickerShowsCameraUnavailable() {
        XCTAssertEqual(DocumentCamera.blockingCopyKey(pickerAvailable: false, hasCaptureDevice: true, permissionDenied: false), CredflareSpec.CopyKey.errorsCameraUnavailable)
    }

    func testDeniedPermissionShowsCameraDenied() {
        XCTAssertEqual(DocumentCamera.blockingCopyKey(pickerAvailable: true, hasCaptureDevice: true, permissionDenied: true), CredflareSpec.CopyKey.errorsCameraDenied)
    }

    func testWorkingCameraOpens() {
        XCTAssertNil(DocumentCamera.blockingCopyKey(pickerAvailable: true, hasCaptureDevice: true, permissionDenied: false))
    }
}
