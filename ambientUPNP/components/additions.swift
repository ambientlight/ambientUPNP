//
//  additions.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 9/2/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

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