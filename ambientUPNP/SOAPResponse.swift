//
//  SOAPResponse.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 6/4/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation


class SOAPResponse:SOAPMessage {
    
    enum Error: ErrorType {
        case SOAPResponseResponseError(errorCode:Int)
    }
    
    let statusCode:Int
    let statusMessage:String
    
    var actionNameº:String?
    var serviceTypeº:String?
    var arguments:[String: String] = [String: String]()
    
    var errorCodeº:Int?
    var errorDescriptionº:String?
    
    init(httpResponse: NSHTTPURLResponse, bodyData:NSData){
        
        self.statusCode = httpResponse.statusCode
        self.statusMessage = NSHTTPURLResponse.localizedStringForStatusCode(httpResponse.statusCode)
        //self.xmlBody = bodyData
        
        var responseHeaders = [SOAPHeaderField: String]()
        var responseOtherHeaders = [String: String]()
        
        for headerKey in httpResponse.allHeaderFields.keys {
            if let headerKeyStringValue = headerKey as? String,
               let valueString = httpResponse.allHeaderFields[headerKey] as? String {
                
                if let soapHeader = SOAPHeaderField(rawValue: headerKeyStringValue.uppercaseString){
                    responseHeaders[soapHeader] = valueString
                } else {
                    responseOtherHeaders[headerKeyStringValue] = valueString
                }
            
            }
        }
        
        
        super.init(headers: responseHeaders, httpVersion: UPNPVersion(major: 1, minor: 0))
        self.unrecognizedHeaders = responseOtherHeaders
        
        let responseXMLObject = XMLSerialization.XMLObjectWithDataº(bodyData)
        if let actionOrErrorElement = responseXMLObject?.firstChildElementThatContains(name: bodyTag)?.childElements.first {
            // parsing error
            if actionOrErrorElement.name.containsString("Fault"){
                
                if let errorInfoElement = actionOrErrorElement.childElement(name: "detail")?.childElement(name: "UPnPError"){
                    if let errorCodeString = errorInfoElement.childElement(name: "errorCode")?.valueº,
                       let errorDescriptionString = errorInfoElement.childElement(name: "errorDescription")?.valueº {
                        
                        self.errorCodeº = Int(errorCodeString)
                        self.errorDescriptionº = errorDescriptionString
                    }
                }
            // parsing correct response
            } else {
                
                let nameComponents = actionOrErrorElement.name.componentsSeparatedByString(":")
                if (nameComponents.count == 2){
                    
                    self.actionNameº = nameComponents[1].stringByReplacingOccurrencesOfString("Response", withString: "")
                    self.serviceTypeº = actionOrErrorElement.attributes.values.first
                    
                    for argumentChild in actionOrErrorElement.childElements {
                        if let argumentValue = argumentChild.valueº {
                            self.arguments[argumentChild.name] = argumentValue
                        }
                    }
                }
            }
            
        }
        
        ////
    }
}
