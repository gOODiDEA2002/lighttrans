import XCTest
import LightTransCore

final class KeychainHelperTests: XCTestCase {
    private var service = ""
    private let account = "apiKey"

    override func setUp() {
        super.setUp()
        service = "LightTrans.Tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        KeychainHelper.delete(service: service, account: account)
        super.tearDown()
    }

    func testSaveAddsAndReadsValue() throws {
        try KeychainHelper.save("first-key", service: service, account: account)

        XCTAssertEqual(try KeychainHelper.read(service: service, account: account), "first-key")
    }

    func testSaveUpdatesExistingValue() throws {
        try KeychainHelper.save("first-key", service: service, account: account)
        try KeychainHelper.save("second-key", service: service, account: account)

        XCTAssertEqual(try KeychainHelper.read(service: service, account: account), "second-key")
    }

    func testDeleteRemovesValue() throws {
        try KeychainHelper.save("temporary-key", service: service, account: account)

        KeychainHelper.delete(service: service, account: account)

        XCTAssertNil(try KeychainHelper.read(service: service, account: account))
    }
}
