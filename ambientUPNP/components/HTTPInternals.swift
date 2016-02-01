//
//  HTTPInternals.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 1/11/16.
//  Copyright © 2016 ambientlight. All rights reserved.
//

import Foundation

public class HTTPMessage {
    
    private enum _ParsingPhase {
        case ControlLine
        case Headers
        case MessageBody
        case ParsingDone
    }
    
    enum Error:ErrorType {
        case FragmentReadFromDifferentSender
        case UTF8DataToStringConversionError
    }
    
    public let controlLineElements: [String]
    public let headers: [String:String]
    public let body: String
    public var bodyData: NSData? {
        return self.body.dataUsingEncoding(NSUTF8StringEncoding)
    }
    
    public private(set) var senderAddress: sockaddr_in?
    
    init(controlLineElements: [String], headers: [String: String], body:String, senderAddress: sockaddr_in? = nil){
        
        self.controlLineElements = controlLineElements
        self.headers = headers
        self.body = body
        
        self.senderAddress = senderAddress
    }
    
    public class func readHTTPMessage(fromStreamSocket socket: SocketFD) throws -> HTTPMessage {
        
        let (controlLineElements, headers, messageBody, readSourceº) = try _readHTTPMessageComponents(fromStreamSocket: socket)
        return HTTPMessage(controlLineElements: controlLineElements, headers: headers, body: messageBody, senderAddress: readSourceº)
    }
    
    private class func _readHTTPMessageComponents(fromStreamSocket socket: SocketFD) throws -> ([String], [String: String], String, sockaddr_in?) {
        
        var controlLineElements = [String]()
        var headers = [String: String]()
        var currentHeader = String()
        var messageBody = String()
        
        var isParsingCRLF = false
        var didJustParsedCRLF = false
        var didReachColon = false
        var didReachSymbolAfterColon = false
        var contentLengthToRead:UInt = 0
        
        var readSourceº:sockaddr_in?
        var parsingPhase:_ParsingPhase = .ControlLine
        var currentString = String()
        while (parsingPhase != .ParsingDone){
            
            let (readByte, readAddress) = try PosixInternals.recvData(socket, readSize: 1)
            if let readSource = readSourceº where readSource != readAddress {
                throw Error.FragmentReadFromDifferentSender
            } else {
                readSourceº = readAddress
            }
            
            
            guard let readChar = String(data: readByte, encoding: NSUTF8StringEncoding) else {
                throw Error.UTF8DataToStringConversionError
            }
            
            if (parsingPhase == .MessageBody){
                
                currentString += readChar
                contentLengthToRead -= 1
                
                if (contentLengthToRead == 0){
                    //return the http message
                    messageBody = currentString
                    parsingPhase = .ParsingDone
                    
                    currentString = String()
                    break
                }
                
            } else if (readChar == "\r"){
                isParsingCRLF = true
            } else if (readChar == "\n" && isParsingCRLF){
                if (didJustParsedCRLF){
                    //double end-char found. parsing body
                    parsingPhase = .MessageBody
                    
                    if let contentLengthString = headers["Content-Length".uppercaseString] {
                        if let contentLength = UInt(contentLengthString){
                            contentLengthToRead = contentLength
                        }
                    }
                    
                    if (contentLengthToRead == 0){
                        //return the HTTP message
                        messageBody = currentString
                        parsingPhase = .ParsingDone
                        
                        currentString = String()
                        break
                    }
                    
                } else {
                    didJustParsedCRLF = true
                    
                    switch(parsingPhase){
                    case .ControlLine:
                        parsingPhase = .Headers
                        controlLineElements.append(currentString)
                        currentString = String()
                    case .Headers:
                        headers[currentHeader.uppercaseString] = currentString
                        didReachColon = false
                        didReachSymbolAfterColon = false
                        currentString = String()
                    default:
                        break
                    }
                }
            } else {
                
                didJustParsedCRLF = false
                
                switch(parsingPhase){
                case .ControlLine:
                    
                    if (readChar != " "){
                        currentString += readChar
                    } else {
                        controlLineElements.append(currentString)
                        currentString = String()
                    }
                    
                case .Headers:
                    
                    if (readChar == " " && !didReachSymbolAfterColon){
                        //skip or verify if this happens in the right place
                    } else if (readChar != ":" || didReachColon){
                        currentString += readChar
                        
                        if (didReachColon){
                            didReachSymbolAfterColon = true
                        }
                    } else if (!didReachColon) {
                        currentHeader = currentString
                        currentString = String()
                        
                        didReachColon = true
                    }
                    
                default:
                    break
                }
            }
        }
        
        return (controlLineElements, headers, messageBody, readSourceº)
    }

    
}

public class HTTPRequest: HTTPMessage {
    
    public enum Error: ErrorType {
        case VersionIsInvalid
        case RequestLineElementsAreInvalid
    }
    
    public enum RequestHeader: String {
        case Accept = "ACCEPT"
        case AcceptCharset = "ACCEPT-CHARSET"
        case AcceptEncoding = "ACCEPT-ENCODING"
        case AcceptLanguage = "ACCEPT-LANGUAGE"
        case AcceptDatetime = "ACCEPT-DATETIME"
        case Authorization = "AUTHORIZATION"
        case CacheControl = "CACHE-CONTROL"
        case Connection = "CONNECTION"
        case Cookie = "COOKIE"
        case ContentLength = "CONTENT-LENGTH"
        case ContentMD5 = "CONTENT-MD5"
        case ContentType = "CONTENT-TYPE"
        case Date = "DATE"
        case Expect = "EXPECT"
        case Forwarded = "FORWARDED"
        case From = "FROM"
        case Host = "HOST"
        case IfMatch = "IF-MATCH"
        case IfModifiedSince = "IF-MODIFIED-SINCE"
        case IfNoneMatch = "IF-NONE-MATCH"
        case IfRange = "IF-RANGE"
        case IfUnmodifiedSince = "IF-UNMODIFIED-SINCE"
        case MaxForwards = "MAX-FORWARDS"
        case Origin = "ORIGIN"
        case Pragma = "PRAGMA"
        case ProxyAuthorization = "PROXY-AUTHORIZATION"
        case Range = "RANGE"
        case Referer = "REFERER"
        case TE = "TE"
        case UserAgent = "USER-AGENT"
        case Upgrade = "UPGRADE"
        case Via = "VIA"
        case Warning = "WARNING"
    }
    
    public var method: String {
        return self.controlLineElements[0]
    }
    
    public var requestPath: String {
        return self.controlLineElements[1]
    }
    
    public let version: HTTPVersion
    
    public var requestHeaders: [RequestHeader: String]{
        
        var requestHeaders = [RequestHeader: String]()
        for (header, headerValue) in self.headers {
            if let standartHeader = RequestHeader(rawValue: header.uppercaseString){
                requestHeaders[standartHeader] = headerValue
            }
        }
        
        return requestHeaders
    }
    
    public var nonStandartRequestHeaders: [String: String]{
        
        var nonStandartRequestHeaders = [String: String]()
        for (header, headerValue) in self.headers {
            if (RequestHeader(rawValue: header.uppercaseString) == nil){
                nonStandartRequestHeaders[header] = headerValue
            }
        }
        
        return nonStandartRequestHeaders
    }
    
    required public init(requestLineElements: [String], headers: [String : String], body: String, senderAddress: sockaddr_in? = nil) throws {
        
        if (requestLineElements.count != 3){
            self.version = HTTPVersion(major: 0, minor: 0)
            super.init(controlLineElements: requestLineElements, headers: headers, body: body, senderAddress: senderAddress)
            
            throw Error.RequestLineElementsAreInvalid
        }
        guard let parsedVersion = HTTPVersion.fromString(requestLineElements[2]) else {
            self.version = HTTPVersion(major: 0, minor: 0)
            super.init(controlLineElements: requestLineElements, headers: headers, body: body, senderAddress: senderAddress)
            
            throw Error.VersionIsInvalid
        }
        
        self.version = parsedVersion
        super.init(controlLineElements: requestLineElements, headers: headers, body: body, senderAddress: senderAddress)
    }
    
    public override class func readHTTPMessage(fromStreamSocket socket: SocketFD) throws -> HTTPRequest {
        
        let (controlLineElements, headers, messageBody, readSourceº) = try _readHTTPMessageComponents(fromStreamSocket: socket)
        return try HTTPRequest(requestLineElements: controlLineElements, headers: headers, body: messageBody, senderAddress: readSourceº)
    }
}


public class HTTPResponse: HTTPMessage {
    
    public enum Error: ErrorType {
        case VersionIsInvalid
        case StatusLineElementsAreInvalid
        case StatusCodeIsNotANumber
    }
    
    public enum ResponseHeader: String {
        case AccessControlAllowOrigin = "ACCESS-CONTROL-ALLOW-ORIGIN"
        case AcceptPatch = "ACCEPT-PATCH"
        case AcceptRanges = "ACCEPT-RANGES"
        case Age = "AGE"
        case Allow = "ALLOW"
        case CacheControl = "CACHE-CONTROL"
        case Connection = "CONNECTION"
        case ContentDisposition = "CONTENT-DISPOSITION"
        case ContentEncoding = "CONTENT-ENCODING"
        case ContentLanguage = "CONTENT-LANGUAGE"
        case ContentLength = "CONTENT-LENGTH"
        case ContentLocation = "CONTENT-LOCATION"
        case ContentMD5 = "CONTENT-MD5"
        case ContentRange = "CONTENT-RANGE"
        case ContentType = "CONTENT-TYPE"
        case Date = "DATE"
        case ETag = "ETAG"
        case Expires = "EXPIRES"
        case LastModified = "LAST-MODIFIED"
        case Link = "LINK"
        case Location = "LOCATION"
        case P3P = "P3P"
        case Pragma = "PRAGMA"
        case ProxyAuthentica = "PROXY-AUTHENTICA"
        case PublicKeyPins = "PUBLIC-KEY-PINS"
        case Refresh = "REFRESH"
        case RetryAfter = "RETRY-AFTER"
        case Server = "SERVER"
        case SetCookie = "SET-COOKIE"
        case Status = "STATUS"
        case StrictTransportSecurity = "STRICT-TRANSPORT-SECURITY"
        case Trailer = "TRAILER"
        case TransferEncoding = "TRANSFER-ENCODING"
        case TSV = "TSV"
        case Upgrade = "UPGRADE"
        case Vary = "VARY"
        case Via = "VIA"
        case Warning = "WARNING"
        case WWWAuthenticate = "WWW-AUTHENTICATE"
        case XFrameOptions = "X-FRAME-OPTIONS"
    }
    
    public let version:HTTPVersion
    public var statusCode: UInt
    public let underlyingStatusDescription: String
    public var localizedAssociatedStatusDescription: String {
        return NSHTTPURLResponse.localizedStringForStatusCode(Int(self.statusCode))
    }
    
    required public init(statusLineElements: [String], headers: [String : String], body: String, senderAddress: sockaddr_in?) throws {
        
        if (statusLineElements.count < 3){
            self.version = HTTPVersion(major: 0, minor: 0)
            self.statusCode = 0
            self.underlyingStatusDescription = String()
            super.init(controlLineElements: statusLineElements, headers: headers, body: body, senderAddress: senderAddress)
            
            throw Error.StatusLineElementsAreInvalid
        }
        
        guard let version = HTTPVersion.fromString(statusLineElements[0]) else {
            self.version = HTTPVersion(major: 0, minor: 0)
            self.statusCode = 0
            self.underlyingStatusDescription = String()
            super.init(controlLineElements: statusLineElements, headers: headers, body: body, senderAddress: senderAddress)
            
            throw Error.VersionIsInvalid
        }
        
        self.version = version
        guard let statusCode = UInt(statusLineElements[1]) else {
            self.statusCode = 0
            self.underlyingStatusDescription = String()
            super.init(controlLineElements: statusLineElements, headers: headers, body: body, senderAddress: senderAddress)
            
            throw Error.StatusCodeIsNotANumber
        }
        
        self.statusCode = statusCode
        let statusDescriptionComponents = Array(statusLineElements[2...statusLineElements.count-1])
        self.underlyingStatusDescription = (statusDescriptionComponents as NSArray).componentsJoinedByString(" ")
        
        super.init(controlLineElements: statusLineElements, headers: headers, body: body, senderAddress: senderAddress)
    }
    
    public override class func readHTTPMessage(fromStreamSocket socket: SocketFD) throws -> HTTPResponse {
        
        let (controlLineElements, headers, messageBody, readSourceº) = try _readHTTPMessageComponents(fromStreamSocket: socket)
        return try HTTPResponse(statusLineElements: controlLineElements, headers: headers, body: messageBody, senderAddress: readSourceº)
    }
}

public struct HTTPVersion {
    public let major: UInt
    public let minor: UInt
    
    init(major: UInt, minor: UInt){
        self.major = major
        self.minor = minor
    }
    
    public static func fromString(string: String) -> HTTPVersion? {
        
        var versionComponents:[String] = string.stringByReplacingOccurrencesOfString("HTTP/", withString: String()).componentsSeparatedByString(".")
        if (versionComponents.count == 2 && Int(versionComponents[0]) != nil && Int(versionComponents[1]) != nil){
            return HTTPVersion(major: UInt(versionComponents[0])!, minor: UInt(versionComponents[0])!)
        }
        
        return nil
    }
}

extension HTTPVersion: Equatable {}
public func ==(lhs: HTTPVersion, rhs: HTTPVersion) -> Bool {
    return (lhs.major == rhs.major && lhs.minor == rhs.minor)
}
