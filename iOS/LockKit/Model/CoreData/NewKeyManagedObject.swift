//
//  NewKeyManagedObject.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 9/8/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import CoreData
import CoreLock

public final class NewKeyManagedObject: NSManagedObject {
    
    internal convenience init(_ value: NewKey, lock: LockManagedObject, context: NSManagedObjectContext) {
        self.init(context: context)
        self.identifier = value.identifier
        self.lock = lock
        self.name = value.name
        self.created = value.created
        self.permission = numericCast(value.permission.type.rawValue)
        if case let .scheduled(schedule) = value.permission {
            self.schedule = .init(schedule, context: context)
        }
        self.expiration = value.expiration
    }
}

// MARK: - IdentifiableManagedObject

extension NewKeyManagedObject: IdentifiableManagedObject { }

// MARK: - Store

internal extension NSManagedObjectContext {
    
    @discardableResult
    func insert(_ newKey: NewKey, for lock: LockManagedObject) throws -> NewKeyManagedObject {
        
        if let managedObject = try find(identifier: newKey.identifier, type: NewKeyManagedObject.self) {
            assert(managedObject.lock == lock, "Key stored with conflicting lock")
            return managedObject
        } else {
            return NewKeyManagedObject(newKey, lock: lock, context: self)
        }
    }
    
    @discardableResult
    func insert(_ key: NewKey, for lock: UUID) throws -> NewKeyManagedObject {
        
        let managedObject = try find(identifier: lock, type: LockManagedObject.self)
            ?? LockManagedObject(identifier: lock, name: "Lock", context: self)
        return try insert(key, for: managedObject)
    }
}
