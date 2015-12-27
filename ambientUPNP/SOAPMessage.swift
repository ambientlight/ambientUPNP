//
//  SOAPMessage.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 6/3/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

public enum SOAPHeaderField: String {
    case Host = "HOST"
    case ContentLength = "CONTENT-LENGTH"
    case ContentType = "CONTENT-TYPE"
    case UserAgent = "USER-AGENT"
    case SoapAction = "SOAPACTION"
    case TransferEncoding = "TRANSFER-ENCODING"
    case Date = "DATE"
    case Server = "SERVER"
}



public class SOAPMessage {
    
    var headers: [SOAPHeaderField: String]
    var unrecognizedHeaders: [String: String] = [String: String]()
    var httpVersion: UPNPVersion
    
    var xmlBodyº: String?
    
    init(headers: [SOAPHeaderField: String], httpVersion:UPNPVersion, soapEnvelopeIdentifier:String = "s", soapActionIdentifier:String = "u"){
        self.headers = headers
        self.httpVersion = httpVersion
        self.soapActionIdentifier = soapActionIdentifier
        self.soapEnvelopeIdentifier = soapEnvelopeIdentifier
    }
    
    //misc
    private(set) var soapEnvelopeIdentifier:String
    private(set) var soapActionIdentifier:String
}