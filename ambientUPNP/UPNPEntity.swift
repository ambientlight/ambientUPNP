//
//  UPNPEntity.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 4/15/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

// all functionality that applies both to devices and services should go here

public class UPNPEntity {
    
    public enum Status {
        case InitError
        case PendingServiceInit
        case Alive
        case Expired
    }
    
    // private var _aliveTimer:
    let identifier:String
    
    // has to be modified by a subclass in its init
    internal(set) var status:Status = .InitError
    
    let descriptionURL: NSURL
    let specVersion: UPNPVersion
    
    // handle expiration in UPNPDevice, UPNPService implementation
    internal(set) var expirationTimer:DispatchTimer?
    
    init(identifier:String, descriptionURL: NSURL, specVersion: UPNPVersion){
        self.identifier = identifier
        self.descriptionURL = descriptionURL
        self.specVersion = specVersion
    }
}

