//
//  upnpComponents.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 9/12/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

public enum UPNPComponentError: ErrorType {
    case XMLElementDoesntContainRequiredChildElement
    case StringToUIntConversionError
}

public struct UPNPVersion {
    public let major: UInt
    public let minor: UInt
    
    init(xmlElement: XMLElement) throws {
        guard let minorString = xmlElement.childElement(name: "minor")?.valueº,
              let majorString = xmlElement.childElement(name: "major")?.valueº
        else {
            throw UPNPComponentError.XMLElementDoesntContainRequiredChildElement
        }
        
        guard let minor = UInt(minorString),
              let major = UInt(majorString)
        else {
            throw UPNPComponentError.StringToUIntConversionError
        }
        
        self.major = major
        self.minor = minor
    }
    
    init(major: UInt, minor: UInt){
        self.major = major
        self.minor = minor
    }
    
    public static func fromString(string: String) -> UPNPVersion? {
        
        var versionComponents:[String] = string.componentsSeparatedByString(".")
        if (versionComponents.count == 2 && Int(versionComponents[0]) != nil && Int(versionComponents[1]) != nil){
            return UPNPVersion(major: UInt(versionComponents[0])!, minor: UInt(versionComponents[0])!)
        }
        
        return nil
    }
}

extension UPNPVersion: Equatable {}

public func ==(lhs: UPNPVersion, rhs: UPNPVersion) -> Bool {
    return (lhs.major == rhs.major && lhs.minor == rhs.minor)
}

public struct UPNPServicePartialDescription {
    
    public let serviceType: String
    public let serviceId: String
    
    public let SCPDURLRelativePath: String
    public let controlURLRelativePath: String
    public let eventSubURLRelativePath: String
    
    init(xmlElement: XMLElement) throws {
        
        guard let serviceType = xmlElement.childElement(name: "serviceType")?.valueº,
              let serviceId = xmlElement.childElement(name: "serviceId")?.valueº,
              let scpdURLString = xmlElement.childElement(name: "SCPDURL")?.valueº,
              let controlURLString = xmlElement.childElement(name: "controlURL")?.valueº,
              let eventSubURLString = xmlElement.childElement(name: "eventSubURL")?.valueº
        else {
            throw UPNPComponentError.XMLElementDoesntContainRequiredChildElement
        }
        
        self.serviceType = serviceType
        self.serviceId = serviceId
        self.SCPDURLRelativePath = _relativePath(scpdURLString)
        self.controlURLRelativePath = _relativePath(controlURLString)
        self.eventSubURLRelativePath = _relativePath(eventSubURLString)
    }
}


public struct UPNPIconDescription {
    
    public let mimetype: String
    public let width:UInt
    public let height:UInt
    public let depth:UInt
    
    public let urlRelativePath:String
    
    public var image:UIImage?
    
    init(xmlElement: XMLElement) throws {
        guard let widthString = xmlElement.childElement(name: "width")?.valueº,
              let heightString = xmlElement.childElement(name: "height")?.valueº,
              let depthString = xmlElement.childElement(name: "depth")?.valueº,
              let mimetypeString = xmlElement.childElement(name: "mimetype")?.valueº,
              let urlString = xmlElement.childElement(name: "url")?.valueº
        else {
            throw UPNPComponentError.XMLElementDoesntContainRequiredChildElement
        }
        
        guard let width = UInt(widthString),
              let height = UInt(heightString),
              let depth = UInt(depthString)
        else {
            throw UPNPComponentError.StringToUIntConversionError
        }
        
        self.width = width
        self.height = height
        self.depth = depth
        self.mimetype = mimetypeString
        self.urlRelativePath = _relativePath(urlString)
    }
}

private func _relativePath(urlString:String) -> String {
    
    var relativePath:String = urlString
    
    var didExtractPathComponent = false
    if let url = NSURL(string: urlString){
        if (url.host != nil) {
            if let pathComponents = url.pathComponents {
                if let range = url.absoluteString.rangeOfString(pathComponents[1]){
                    relativePath = urlString.substringFromIndex(range.startIndex)
                    didExtractPathComponent = true
                }
            }
        }
    }
    
    if (!didExtractPathComponent && urlString[urlString.startIndex] == "/"){
        relativePath = urlString.substringFromIndex(urlString.startIndex.advancedBy(1))
    }
    
    return relativePath
}