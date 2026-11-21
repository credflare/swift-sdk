import XCTest
import SwiftUI
@testable import CredflareSDK

final class SpecTests: XCTestCase {
    func testEveryIconPathParsesCompletely() {
        for (name, icon) in CredflareSpec.Icons.all {
            for path in icon.paths {
                let commands = SpecPathParser.parse(path.d)
                XCTAssertFalse(commands.isEmpty, name)
                guard case .move = commands.first else { return XCTFail("\(name) does not start with a move") }
                let letters = path.d.filter { "MLCZ".contains($0) }.count
                XCTAssertEqual(commands.count, letters, name)
                XCTAssertFalse(SpecPathShape(path.d, viewBox: icon.viewBox).path(in: CGRect(x: 0, y: 0, width: 48, height: 48)).isEmpty, name)
            }
        }
    }

    func testPathParserReadsAbsoluteCommands() {
        XCTAssertEqual(SpecPathParser.parse("M 14.5 6 L 8.5 12 L 14.5 18"), [.move(CGPoint(x: 14.5, y: 6)), .line(CGPoint(x: 8.5, y: 12)), .line(CGPoint(x: 14.5, y: 18))])
        XCTAssertEqual(SpecPathParser.parse("M1-2C3,4 5,6 7,8Z"), [.move(CGPoint(x: 1, y: -2)), .curve(CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 6), CGPoint(x: 7, y: 8)), .close])
    }

    func testCopyFillsPlaceholdersAndFallsBackForTheVerifier() {
        XCTAssertEqual(CredflareCopy.text(CredflareSpec.CopyKey.selfiePrivacy, ["verifier": CredflareCopy.verifier("Acme Bank")]), "Your selfie will be sent to Acme Bank for review.")
        XCTAssertEqual(CredflareCopy.text(CredflareSpec.CopyKey.selfiePrivacy, ["verifier": CredflareCopy.verifier(nil)]), "Your selfie will be sent to your verifier for review.")
        XCTAssertEqual(CredflareCopy.verifier("  "), "your verifier")
        XCTAssertEqual(CredflareCopy.text(CredflareSpec.CopyKey.livenessProgress, ["current": "2", "total": "3"]), "Movement 2 of 3")
    }

    func testTokensDriveTheThemeInBothSchemes() {
        XCTAssertEqual(CredflareTheme(.light).palette, CredflareSpec.Tokens.light)
        XCTAssertEqual(CredflareTheme(.dark).palette, CredflareSpec.Tokens.dark)
        XCTAssertEqual(CredflareSpec.Tokens.textAlign, "center")
    }
}
