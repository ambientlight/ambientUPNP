//
//  additions.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 9/2/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

func synchronized(lockedObject: AnyObject, closure: () -> Void) {
    objc_sync_enter(lockedObject)
    defer { objc_sync_exit(lockedObject) }
    
    closure()
}

func synchronized(lockedObject: AnyObject, closure: () throws -> Void) throws {
    objc_sync_enter(lockedObject)
    defer { objc_sync_exit(lockedObject) }
    
    try closure()
}

extension UInt {
    
    func iterate(block:()->Void){
        for _ in 0..<self {
            block()
        }
    }
    
    func iterate(block:(it:UInt)->Void){
        for i:UInt in 0..<self {
            block(it: i)
        }
    }
}

extension String {
    func toBool() -> Bool? {
        switch self {
        case "True", "true", "yes", "1":
            return true
        case "False", "false", "no", "0":
            return false
        default:
            return nil
        }
    }
}