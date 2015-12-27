//
//  GENAMessage.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 12/27/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

let UPNPEventNotificationType = "upnp:event"
let UPNPPropertyChangeNotificationSubtype = "upnp:propchange"
private let HTTPVersionString = "HTTP/1.1"


private let headerBodySeperator = "\\r\\n\\r\\n"
private let requestLinePattern = "^(\\w[\\w-]*)\\s([\\d\\w\\+\\*\\&@#\\/%\\?=~_\\|!:\\.;]+)\\s(?:HTTP\\/)(\\d\\.\\d)\\r\\n"
private let responsePattern = "(?:HTTP\\/)(\\d\\.\\d)\\s(\\d+)\\s([^\\r\\n]*)\\r\\n"

private let headerPattern = "(\\w[\\w\\d-]*):\\s*([^\\r\\n]+)\\r\\n"



public struct GENAMessage {
    
    public enum Method: String {
        case NOTIFY = "NOTIFY"
        case SUBSCRIBE = "SUBSCRIBE"
        case UNSUBSCRIBE = "UNSUBSCRIBE"
    }
    
    public enum HeaderField: String {
        
        case Host = "HOST"
        case CacheControl = "CACHE-CONTROL"
        case Location = "LOCATION"
        case UserAgent = "USER-AGENT"
        case Date = "DATE"
        case Server = "SERVER"
        case ContentLength = "CONTENT-LENGTH"
        case ContentType = "CONTENT-TYPE"
        case TransferEncoding = "TRANSFER-ENCODING"
        case Connection = "CONNECTION"
        
        case Callback = "CALLBACK"
        case NT = "NT"
        case NTS = "NTS"
        case SID = "SID"
        case SEQ = "SEQ"
        case Timeout = "TIMEOUT"
        case Statevar = "STATEVAR"
        case AcceptedStatevar = "ACCEPTED-STATEVAR"
        
        case USN = "USN"
        case SVCID = "SVCID"
        case LVL = "LVL"
        case BootID = "BOOTID.UPNP.ORG"
    }
    
    enum Error:ErrorType {
        case WrongEncoding
        case BadMessageFormat
        
        case MethodNotRecognized
        case VersionNotRecognized
    }

    
    public var method: Method
    
    // response-specific
    public var statusCode: UInt
    public var statusMessage: String
    
    public var isRequest: Bool
    
    public var httpVersion: UPNPVersion
    public var headers: Dictionary<HeaderField, String>
    public var unrecognizedHeaders: Dictionary<String, String>
    
    //address of this message sender
    public var originatorAddress: sockaddr_in?
    
    public var propertySet = [String: String]()
    
    public static func messageWithData(data: NSData, senderAddress: sockaddr_in? = nil) throws -> GENAMessage {
        
        guard let dataString = String(data: data, encoding: NSASCIIStringEncoding) else {
            throw Error.WrongEncoding
        }
        
        if (try NSRegularExpression.numberOfMatchesInString(dataString as String, pattern: headerBodySeperator) != 1){
            //warning: there should be only one blank line, the message is messed up
            throw Error.BadMessageFormat
        }
        
        guard let messageHeaderString = try NSRegularExpression.stringBeforeAndIncludingFirstMatchOfString(dataString, pattern: headerBodySeperator) else {
            throw Error.BadMessageFormat
        }
        
        guard let messageBodyString = try NSRegularExpression.stringAfterFirstMatchOfString(dataString, pattern: headerBodySeperator) else {
            throw Error.BadMessageFormat
        }
        
        if let requestLineElements = try NSRegularExpression.capturingGroupsOfStringFirstMatch(messageHeaderString, pattern: requestLinePattern){
            
            if (requestLineElements.count != 3){
                // METHOD URL HTTP/major.minor, otherwise something's wrong
                throw SSDPMessage.Error.BadMessageFormat
            }
            
            guard let method = GENAMessage.Method(rawValue: requestLineElements[0]) else {
                throw SSDPMessage.Error.MethodNotRecognized
            }
            
            guard let httpVersion = UPNPVersion.fromString(requestLineElements[2]) else {
                throw SSDPMessage.Error.VersionNotRecognized
            }

            var headerDict = [HeaderField: String]()
            var unrecognizedHeaderDict = [String: String]()
            try! NSRegularExpression.capturingGroupsOfStringForEachMatch(messageHeaderString, pattern: headerPattern) { (captureGroups: [String]) in
                if let parsedField = GENAMessage.HeaderField(rawValue: captureGroups[0].uppercaseString) {
                    headerDict[parsedField] = captureGroups[1]
                } else {
                    unrecognizedHeaderDict[captureGroups[0]] = captureGroups[1]
                }
            }
        
            let propertySet = _propertySetFromString(messageBodyString)
            return GENAMessage(method: method, statusCode: 0, statusMessage: String(), isRequest: true, httpVersion: httpVersion, headers: headerDict, unrecognizedHeaders: unrecognizedHeaderDict, originatorAddress: senderAddress, propertySet: propertySet)
            
            
        } else {
            throw SSDPMessage.Error.BadMessageFormat
        }
    }
    
    public static func httpResponseOKData() -> NSData? {
        
        let crlf = "\r\n"
        var dataString = String()
        
        let sucessStatusCode:UInt = 200
        let successMessage = "OK"
        
        dataString += "\(HTTPVersionString) \(sucessStatusCode) \(successMessage)\(crlf)"
        dataString += crlf
        
        return dataString.dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: false)
    }
    
    
    private static func _propertySetFromString(bodyString: String) -> [String: String] {
        
        var propertySet = [String: String]()
        
        if let propertySetData = bodyString.dataUsingEncoding(NSUTF8StringEncoding) {
            if let propertyElements = XMLSerialization.XMLObjectWithDataº(propertySetData)?.childElements {
                for propertyContainerElement in propertyElements {
                    if let propertyValueElement = propertyContainerElement.childElements.first {
                        if let propertyValue = propertyValueElement.valueº {
                            propertySet[propertyValueElement.name] = propertyValue
                        }
                    }
                }
            }
        }
        
        return propertySet
    }
}


//MARK: Extension - conventient getters for headers
extension GENAMessage {
    
    public var subscriptionIdentifierº:String? {
        return self.headers[.SID]
    }
    
    
    
}

