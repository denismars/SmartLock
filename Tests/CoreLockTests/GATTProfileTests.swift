//
//  GATTProfileTests.swift
//  CoreLockTests
//
//  Created by Alsey Coleman Miller on 8/11/18.
//

import Foundation
import XCTest
import Bluetooth
import TLVCoding
@testable import CoreLock

final class GATTProfileTests: XCTestCase {
    
    static let allTests = [
        ("testInformation", testInformation),
        ("testUnlock", testUnlock),
        ("testSetup", testSetup)
    ]

    func testInformation() {
        
        let information = LockInformationCharacteristic(identifier: UUID(),
                                                    status: .setup)
        
        guard let decoded = LockInformationCharacteristic(data: information.data)
            else { XCTFail("Could not parse bytes"); return }
        
        XCTAssertEqual(information, decoded)
    }
    
    func testUnlock() {
        
        let key = (identifier: UUID(), secret: KeyData())
        
        let authentication = Authentication(key: key.secret)
        
        let characteristic = UnlockCharacteristic(
            identifier: key.identifier,
            authentication: authentication
        )
        
        guard let decoded = UnlockCharacteristic(data: characteristic.data)
            else { XCTFail("Could not parse bytes"); return }
        
        XCTAssertEqual(characteristic, decoded)
        XCTAssertEqual(try! TLVEncoder.lock.encode(decoded.authentication),
                       try! TLVEncoder.lock.encode(authentication))
        XCTAssert(decoded.authentication.isAuthenticated(with: key.secret))
        XCTAssert(characteristic.authentication.isAuthenticated(with: key.secret))
        XCTAssertFalse(Authentication(key: KeyData()).isAuthenticated(with: key.secret))
    }
    
    func testSetup() {
        
        let deviceSharedSecret = KeyData()
        
        let request = SetupRequest()
        
        let characteristic = try! SetupCharacteristic(request: request, sharedSecret: deviceSharedSecret)
        
        guard let decoded = SetupCharacteristic(data: characteristic.data)
            else { XCTFail("Could not parse bytes"); return }
        
        XCTAssertEqual(try! TLVEncoder.lock.encode(decoded.encryptedData),
                       try! TLVEncoder.lock.encode(characteristic.encryptedData))
        
        let decrypted = try! decoded.decrypt(with: deviceSharedSecret)
        
        XCTAssertEqual(request, decrypted)
        XCTAssertEqual(request.identifier, decrypted.identifier)
        XCTAssertEqual(request.secret, decrypted.secret)
    }
}
