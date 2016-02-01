//
//  SSDPMessage.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 4/10/15.
//  reviewed on 9/3/15 by ambientlight.
//
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

let SSDPSearchTargetAll = "ssdp:all"
let SSDPSearchTargetRootDevice = "upnp:rootdevice"
let UPNPVersionString = "UPnP/1.1"

private let HTTPVersionString = "HTTP/1.1"


private let headerBodySeperator = "\\r\\n\\r\\n"
private let requestLinePattern = "^(\\w[\\w-]*)\\s([\\d\\w\\+\\*\\&@#\\/%\\?=~_\\|!:\\.;]+)\\s(?:HTTP\\/)(\\d\\.\\d)\\r\\n"
private let responsePattern = "(?:HTTP\\/)(\\d\\.\\d)\\s(\\d+)\\s([^\\r\\n]*)\\r\\n"

private let headerPattern = "(\\w[\\w\\d-]*):\\s*([^\\r\\n]+)\\r\\n"

public struct SSDPMessage {
    
    //MARK: enum - Method
    public enum Method: String {
        case NOTIFY = "NOTIFY"
        case MSEARCH = "M-SEARCH"
        case NONE = ""
    }
    
    //MARK: enum - HeaderField
    public enum HeaderField: String {
        case Host = "HOST"
        case CacheControl = "CACHE-CONTROL"
        case Location = "LOCATION"
        case UserAgent = "USER-AGENT"
        case Date = "DATE"
        case Server = "SERVER"
        case ContentLength = "Content-Length"
        
        case EXT = "EXT"
        case MAN = "MAN"
        case MX = "MX"
        case ST = "ST"
        case NT = "NT"
        case NTS = "NTS"
        case USN = "USN"
        case BootID = "BOOTID.UPNP.ORG"
        case NextBootID = "NEXTBOOTID.UPNP.ORG"
        case ConfigID = "CONFIG.UPNP.ORG"
        case SearchPort = "SEARCHPORT.UPNP.ORG"
    }
    
    //MARK: enum - NotificationSubtype
    public enum NotificationSubtype: String {
        case alive = "ssdp:alive"
        case byebye = "ssdp:byebye"
        case update = "ssdp:update"
        case discover = "ssdp:discover"
    }

    //MARK: errorType - Error
    enum Error:ErrorType {
        case WrongEncoding
        case BadMessageFormat
        
        case MethodNotRecognized
        case VersionNotRecognized
    }
    
    //MARK: public: Properties
    // request-specific
    public var method: SSDPMessage.Method
    
    // response-specific
    public var statusCode: UInt
    public var statusMessage: String
    
    public var isRequest: Bool
    
    public var httpVersion: UPNPVersion
    public var headers: Dictionary<SSDPMessage.HeaderField, String>
    public var unrecognizedHeaders: Dictionary<String, String>
    
    //address of this message sender
    public var originatorAddress: sockaddr_in?
    
    public var data:NSData {
        
        let crlf = "\r\n"
        
        var dataString = String()
        if (isRequest){
            dataString += "\(method.rawValue) * \(HTTPVersionString)\(crlf)"
        } else {
            dataString += "\(HTTPVersionString) \(statusCode) \(statusMessage)\(crlf)"
        }
        
        for headerKey:SSDPMessage.HeaderField in headers.keys {
            // if recognized "EXT:" will contain "blank" as header value, which should not be printed
            if headerKey == .EXT {
                dataString += "\(headerKey.rawValue): \(crlf)"
            } else {
                dataString += "\(headerKey.rawValue): \(headers[headerKey]!)\(crlf)"
            }
        }
        
        //When parsing "EXT: " might be ignored(in case "EXT:\r\n"), so when writing out data, we explicitly check for it
        if (!isRequest){
            if !headers.keys.contains(SSDPMessage.HeaderField.EXT){
                dataString += "\(SSDPMessage.HeaderField.EXT.rawValue): \(crlf)"
            }
        }
        
        for headerKey:String in unrecognizedHeaders.keys {
            dataString += "\(headerKey): \(unrecognizedHeaders[headerKey]!)\(crlf)"
        }
        
        
        dataString += crlf
        return dataString.dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: false)!
    }
    
    //MARK: public: Methods
    public static func messageWithData(data: NSData) throws -> SSDPMessage {
        return try messageWithDataAndAddress(data, senderAddress: nil)
    }
    
    public static func messageWithDataAndAddress(data: NSData, senderAddress: sockaddr_in?) throws -> SSDPMessage {
        
        guard let dataString = NSString(data: data, encoding: NSASCIIStringEncoding) else {
            throw SSDPMessage.Error.WrongEncoding
        }
        
        if (try NSRegularExpression.numberOfMatchesInString(dataString as String, pattern: headerBodySeperator) != 1){
            //warning: there should be only one blank line, the message is messed up
            throw SSDPMessage.Error.BadMessageFormat
        }
        
        guard var requestMessageHeaderString = try NSRegularExpression.stringBeforeAndIncludingFirstMatchOfString(dataString as String, pattern: headerBodySeperator) else {
            throw SSDPMessage.Error.BadMessageFormat
        }
        
        // adding symbol to annoying "EXT: " for simplified parsing ("EXT: blank")
        requestMessageHeaderString = requestMessageHeaderString.stringByReplacingOccurrencesOfString("\r\nEXT:", withString: "\r\nEXT: blank", options: NSStringCompareOptions.CaseInsensitiveSearch)
        
        
        // parsing request method line (method URL version)
        if let requestLineElements = try NSRegularExpression.capturingGroupsOfStringFirstMatch(requestMessageHeaderString, pattern: requestLinePattern){
            
            if (requestLineElements.count != 3){
                // METHOD URL HTTP/major.minor, otherwise something's wrong
                throw SSDPMessage.Error.BadMessageFormat
            }
            
            guard let method = SSDPMessage.Method(rawValue: requestLineElements[0]) else {
                throw SSDPMessage.Error.MethodNotRecognized
            }
            
            guard let version = UPNPVersion.fromString(requestLineElements[2]) else {
                throw SSDPMessage.Error.VersionNotRecognized
            }
            
            // parse headers
            var headerDict = [HeaderField: String]()
            var unrecognizedHeaderDict = [String: String]()
            try! NSRegularExpression.capturingGroupsOfStringForEachMatch(requestMessageHeaderString, pattern: headerPattern) { (captureGroups: [String]) in
                if let parsedField = SSDPMessage.HeaderField(rawValue: captureGroups[0].uppercaseString) {
                    headerDict[parsedField] = captureGroups[1]
                } else {
                    unrecognizedHeaderDict[captureGroups[0]] = captureGroups[1]
                }
            }
            
            return SSDPMessage(method: method, statusCode: 0, statusMessage: String(), isRequest: true, httpVersion: version, headers: headerDict, unrecognizedHeaders: unrecognizedHeaderDict, originatorAddress: senderAddress)
            
            
            // if it is not a request, trying to parse as a response
        } else if let responseLineElements = try NSRegularExpression.capturingGroupsOfStringFirstMatch(requestMessageHeaderString, pattern: responsePattern){
            
            if (responseLineElements.count != 3){
                // HTTP/major.minor STATUS_CODE STATUS_MESSAGE, otherwise something's wrong
                throw SSDPMessage.Error.BadMessageFormat
            }
            
            guard let version = UPNPVersion.fromString(responseLineElements[0]) else {
                throw SSDPMessage.Error.VersionNotRecognized
            }
            
            let statusCode:UInt = UInt(responseLineElements[1])!
            let statusMessage:String = responseLineElements[2]
            
            // parse headers
            var headerDict = [HeaderField: String]()
            var unrecognizedHeaderDict = [String: String]()
            try! NSRegularExpression.capturingGroupsOfStringForEachMatch(requestMessageHeaderString, pattern: headerPattern) { (captureGroups: [String]) in
                if let parsedField = SSDPMessage.HeaderField(rawValue: captureGroups[0].uppercaseString) {
                    headerDict[parsedField] = captureGroups[1]
                } else {
                    unrecognizedHeaderDict[captureGroups[0]] = captureGroups[1]
                }
            }
            
            return SSDPMessage(method: .NONE, statusCode: statusCode, statusMessage: statusMessage, isRequest: false, httpVersion: version, headers: headerDict, unrecognizedHeaders: unrecognizedHeaderDict, originatorAddress: senderAddress)
            
        } else {
            throw SSDPMessage.Error.BadMessageFormat
        }
    }
    
    public static func searchMessageWithSearchTarget(searchTarget: String = SSDPSearchTargetAll, responseMaxWaitTime: UInt = 1, unicastAddressº: sockaddr_in? = nil) -> SSDPMessage {
        
        var message = SSDPMessage(method: .MSEARCH, statusCode: 0, statusMessage: String(), isRequest: true, httpVersion: UPNPVersion(major: 1, minor: 1), headers: [HeaderField: String](), unrecognizedHeaders: [String: String](), originatorAddress: nil)
    
        if let hostAddress = unicastAddressº {
            let addressString = PosixInternals.addressString(hostAddress)
            message.headers[.Host] = String("\(addressString):\(SSDPDefaultPort)")
        } else {
            message.headers[.Host] = String("\(SSDPDefaultMulticastAddressString):\(SSDPDefaultPort)")
        }
        
        message.headers[.MAN] = String("\"\(SSDPMessage.NotificationSubtype.discover.rawValue)\"")
        
        //mxTime is minimum 1, maximum 5
        let mxTime:UInt = (responseMaxWaitTime < 1) ? 1 : ( (responseMaxWaitTime > 5) ? 5 : responseMaxWaitTime);
        
        //MX header is not needed in unicast M-SEARCH
        if unicastAddressº == nil {
            message.headers[.MX] = String("\(mxTime)")
        }
        
        message.headers[.ST] = searchTarget
        message.headers[.ContentLength] = "0"
        
        let iosVersion:NSOperatingSystemVersion = NSProcessInfo.processInfo().operatingSystemVersion
        message.headers[.UserAgent] = "iOS/\(iosVersion.majorVersion).\(iosVersion.minorVersion) \(UPNPVersionString) ambientUPNP/0.1"
        return message
    }
    
}

//MARK: Extension - conventient getters for headers
extension SSDPMessage {
    
    public var hostº:sockaddr_in? {
        
        if let hostString = headers[.Host]{
            var stringComponents = hostString.componentsSeparatedByString(":")
            
            if let port = UInt(stringComponents[1]){
                return sockaddr_in(sin_len: __uint8_t(strideof(sockaddr_in)), sin_family: sa_family_t(AF_INET), sin_port: htons(in_port_t(port)), sin_addr: in_addr(s_addr: inet_addr(stringComponents[0])), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
            }
        }
        
        return nil
    }
    
    
    public var maxAgeº:UInt? {
        
        let maxAgePattern = "\\s*(?:max-age)\\s?=\\s?([\\d]*)\\s*"
        
        if let cacheControlString = headers[.CacheControl]{
            if let captureGroups:[String] = try! NSRegularExpression.capturingGroupsOfStringFirstMatch(cacheControlString, pattern: maxAgePattern){
                
                if (captureGroups.count == 1){
                    if let maxAge = Int(captureGroups[0]){
                        return UInt(maxAge)
                    }
                }
            }
        }
        
        return nil
    }
    
    public var descriptionURLº:NSURL? {
        
        if let locationString = headers[.Location]{
            return NSURL(string: locationString)
        }
        
        return nil
    }
    
    public var notificationTypeº:String? {
        
        if isRequest {
            if method == .MSEARCH {
                return headers[.ST]
            } else {
                return headers[.NT]
            }
            
        } else {
            return headers[.ST]
        }
    }
    
    // ST and NT headers serve essentially identical purposes(ST in NOTIFY, NT in M-SEARCH and its response)
    public var searchTargetº:String? {
        return notificationTypeº
    }
    
    public var notificationSubtypeº:SSDPMessage.NotificationSubtype? {
        
        if isRequest {
            
            if method == .MSEARCH {
                
                if headers[.MAN] == "\"\(SSDPMessage.NotificationSubtype.discover.rawValue)\"" {
                    return .discover
                }
                
            } else {
                
                if let ntsString = headers[.NTS]{
                    if let ntsValue = SSDPMessage.NotificationSubtype(rawValue: ntsString){
                        return ntsValue
                    }
                }
            }
            
        } else {
            return .alive
        }
        
        return nil
    }
    
    public var uniqueServiceNameº:String? {
        return headers[.USN]
    }
    
    public var universallyUniqueIdentifierº:String? {
        
        if let identifierComponents = uniqueServiceNameº?.componentsSeparatedByString("::") {
            if (identifierComponents.count > 0){
                return identifierComponents[0]
            }
        }
        
        return nil
    }
    
    public var entityIdentifierº:String? {
        
        if let identifierComponents = uniqueServiceNameº?.componentsSeparatedByString("::") {
            if (identifierComponents.count > 1){
                return identifierComponents[1]
            }
        }
        
        return nil
    }
    
    // Server or User-Agent
    public var senderInfo:String? {
        
        if method == .MSEARCH {
            return headers[.UserAgent]
        } else {
            return headers[.Server]
        }
    }
}


//MARK: Extention - Printable
extension SSDPMessage:CustomStringConvertible {
    
    public var description:String {
        var dataString = String()
        
        if (isRequest){
            dataString += "Request "
        } else {
            dataString += "Response "
        }
        
        
        if let address = originatorAddress {
            dataString += "from \(PosixInternals.addressString(address)): {\n"
        } else {
            dataString += "{\n"
        }
        
        dataString += NSString(data: self.data, encoding: NSASCIIStringEncoding)! as String
        dataString += "}"
        
        return dataString
    }
}















