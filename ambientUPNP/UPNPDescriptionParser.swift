//
//  UPNPDescriptionParser.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 9/10/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

public class UPNPDescriptionParser: XMLParserDelegate {
    
    private var _parser: XMLParser
    private(set) public var isDeviceDescription: Bool
    
    public init(deviceDescriptionData: NSData){
        
        self.isDeviceDescription = true
        
        _parser = XMLParser(data: deviceDescriptionData)
        _parser.delegateº = self
    }
    
    public init(serviceDescriptionData: NSData){
        
        self.isDeviceDescription = false
        
        _parser = XMLParser(data: serviceDescriptionData)
        _parser.delegateº = self
    }
    
    //MARK: Delegate - XMLParserDelegate
    func parserDidStartDocument(parser: XMLParser) {
        
    }
    
    func parserDidEndDocument(parser: XMLParser) {
    
    }
    
    func parser(parser: XMLParser, didStartElement element: XMLElement) {
        
    }
    
    
    func parser(parser: XMLParser, didEndElement element: XMLElement){
        
    }
    
    func parser(parser: XMLParser, valueFoundInElement element: XMLElement) {
        
    }

    
}