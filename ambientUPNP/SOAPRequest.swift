//
//  SOAPRequest.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 6/3/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

let contentTypeString:String = "text/xml; charset=\"utf-8\""
let envelopeAttributeXMLNS:String = "http://schemas.xmlsoap.org/soap/envelope/"
let envelopeAttributeEncodingStyle:String = "http://schemas.xmlsoap.org/soap/encoding/"

let envelopeTag = "Envelope"
let bodyTag = "Body"

let xmlnsAttribute = "xmlns"
let encodingStyleAttribute = "encodingStyle"

public class SOAPRequest: SOAPMessage {
    
    let controlURL:NSURL
    var hostº:NSURL?
    
    let associatedActionInvocation:UPNPActionInvocation
    
    public init(actionInvocation:UPNPActionInvocation){
        
        self.controlURL = actionInvocation.service.controlURL
        self.hostº = actionInvocation.service.device.hostURL
        self.associatedActionInvocation = actionInvocation
        
        var messageHeaders: [SOAPHeaderField: String] = [SOAPHeaderField: String]()
        if let hostURL = self.hostº {
            messageHeaders[.Host] = hostURL.absoluteString
        } else {
            NSLog("\(self.dynamicType): \(__FUNCTION__): WARN: HostURL is not set. (Couldn't retrieve hostURL of the target device)")
        }
        
        messageHeaders[.ContentType] = contentTypeString
        
        let iosVersion:NSOperatingSystemVersion = NSProcessInfo.processInfo().operatingSystemVersion
        messageHeaders[.UserAgent] = "iOS/\(iosVersion.majorVersion).\(iosVersion.minorVersion) \(UPNPVersionString) ambientUPNP/0.1"
        messageHeaders[.SoapAction] = "\"\(actionInvocation.service.serviceType)#\(actionInvocation.name)\""
        
        super.init(headers: messageHeaders, httpVersion: UPNPVersion(major: 1, minor: 0))
        
        let contentLength = _writeSOAPBody(actionInvocation.service)
        self.headers[.ContentLength] = "\(contentLength)"
    }
    
    private func _writeSOAPBody(invocationService: UPNPService) -> Int {
        
        let envelopeAttributes:[String : String] =
        ["\(xmlnsAttribute):\(soapEnvelopeIdentifier)" : "\(envelopeAttributeXMLNS)",
            "\(soapEnvelopeIdentifier):\(encodingStyleAttribute)" : "\(envelopeAttributeEncodingStyle)"]
        let actionAttribute:[String : String] =
        ["\(xmlnsAttribute):\(soapActionIdentifier)" : "\(invocationService.serviceType)"]
        
        
        let envelopeElement = XMLElement(name:"\(soapEnvelopeIdentifier):\(envelopeTag)", attributes:envelopeAttributes)
        let bodyElement = envelopeElement.addChildElement(name: "\(soapEnvelopeIdentifier):\(bodyTag)")
        let actionElement = bodyElement.addChildElement(name: "\(soapActionIdentifier):\(self.associatedActionInvocation.name)", attributes: actionAttribute)
        
        for argument in self.associatedActionInvocation.arguments {
            if let value = argument.associatedValueº {
                actionElement.addChildElement(name: argument.name, value: value)
            }
        }
        
        let xmlBody = XMLSerialization.stringWithXMLObject(envelopeElement)
        self.xmlBodyº = xmlBody
        return xmlBody.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
    }
    
}
