//
//  LockHardware.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/12/18.
//
//

import Foundation

#if swift(>=3.2)
#elseif swift(>=3.0)
    import Codable
#endif

/// Lock Hardware declaration. 
public struct LockHardware {
    
    /// Lock Model
    public let model: LockModel
    
    /// Lock Hardare Revision
    public let hardwareRevision: String
    
    /// Lock serial number
    public let serialNumber: String
    
    public init(model: LockModel,
                hardwareRevision: String,
                serialNumber: String) {
        
        self.model = model
        self.hardwareRevision = hardwareRevision
        self.serialNumber = serialNumber
    }
}

// MARK: - Darwin

#if os(macOS)
    
    public extension LockHardware {
        
        public static var mac: LockHardware {
            
            return LockHardware(model: .mac,
                                hardwareRevision: UIDevice.current.modelIdentifier,
                                serialNumber: UIDevice.current.serialNumber)
        }
    }
    
#endif

// MARK: - Codable

extension LockHardware: Codable {
    
    public enum CodingKeys: String, CodingKey {
        
        case model
        case hardwareRevision
        case serialNumber
    }
    
    public init(from decoder: Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.model = try container.decode(LockModel.self, forKey: .model)
        self.hardwareRevision = try container.decode(String.self, forKey: .hardwareRevision)
        self.serialNumber = try container.decode(String.self, forKey: .serialNumber)
    }
    
    public func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(model, forKey: .model)
        try container.encode(hardwareRevision, forKey: .hardwareRevision)
        try container.encode(serialNumber, forKey: .serialNumber)
    }
}