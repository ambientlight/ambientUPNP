//
//  XMLInternals.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 7/12/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

let xmlDeclaration = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"

public class XMLSerialization {
    
    public class func XMLObjectWithDataº(data: NSData) -> XMLElement? {
    
        let parser = XMLParser(data: data)
        return parser.rootElementº
    }
    
    public class func dataWithXMLObjectº(rootElement:XMLElement) -> NSData? {
        
        let writer = XMLWriter(rootElement: rootElement)
        return writer.dataº
    }
    
    public class func stringWithXMLObject(rootElement:XMLElement) -> String {
        
        let writer = XMLWriter(rootElement: rootElement)
        return writer.representativeString
    }
}

public class XMLElement {
    
    public init(name: String){
        self.name = name
    }
    
    public init(name: String, value:String){
        self.name = name
        self.valueº = value
    }
    
    public init(name: String, attributes: [String:String]){
        self.name = name
        self.attributes = attributes
    }
    
    public init(name: String, value:String, attributes: [String:String]){
        self.name = name
        self.valueº = value
        self.attributes = attributes
    }
    
    //MARK: PROPERTIES
    
    public var name:String
    public var valueº:String?
    public var attributes:[String: String] = [String: String]()
    
    public var childElements:[XMLElement] = [XMLElement]()
    public weak var parentElementº:XMLElement?
    
    //MARK: METHODS
 
    public func childElement(name name:String) -> XMLElement? {
        let results = self.childElements.filter { (element:XMLElement) in return (element.name == name) }
        return results.first
    }
    
    public func childElements(name name:String) -> [XMLElement] {
        return self.childElements.filter { (element:XMLElement) in return (element.name == name) }
    }
    
    public func firstChildElementThatContains(name name:String) -> XMLElement? {
        let elementsThatContain = self.childElements.filter { (element:XMLElement) in return (element.name.containsString(name)) }
        return elementsThatContain.first
    }
    
    public func addChildElement(name name:String, attributes:[String:String]) -> XMLElement {
        var childElement = XMLElement(name: name, attributes: attributes)
        self.addChildElement(&childElement)
        return childElement
    }
    
    public  func addChildElement(name name:String, value: String) -> XMLElement {
        var childElement = XMLElement(name: name, value: value)
        self.addChildElement(&childElement)
        return childElement
    }
    
    public func addChildElement(name name:String, cdata: String) -> XMLElement {
        var childElement = XMLElement(name: name, value: "<![CDATA[\(cdata)]]>")
        self.addChildElement(&childElement)
        return childElement
    }
    
    public func addChildElement(name name:String) -> XMLElement {
        var childElement = XMLElement(name: name)
        self.addChildElement(&childElement)
        return childElement
    }
    
    public func addChildElement(inout element:XMLElement){
        self.childElements.append(element)
        element.parentElementº = self
    }
    
    public func addChildElements(elements:[XMLElement]){
        self.childElements += elements
        for element in self.childElements {
            element.parentElementº = self
        }
    }
}

//MARK:
//MARK: INTERNAL

//MARK: PROTOCOL: XMLParserDelegate
internal protocol XMLParserDelegate {
    
    func parserDidStartDocument(parser: XMLParser)
    func parserDidEndDocument(parser: XMLParser)
    func parser(parser: XMLParser, didStartElement element: XMLElement)
    func parser(parser: XMLParser, valueFoundInElement element: XMLElement)
    func parser(parser: XMLParser, didEndElement element: XMLElement)
}

//MARK:

internal class XMLParser: NSObject, NSXMLParserDelegate {
    
    private var _parser:NSXMLParser
    private var _rootElementº:XMLElement?
    private weak var _currentElementº:XMLElement?
    
    private var _parsed:Bool = false
    
    init?(contentsOfURL url:NSURL){
        
        if let parser = NSXMLParser(contentsOfURL: url) {
            _parser = parser
            
            super.init()
            _parser.delegate = self
            
        } else {
            NSLog("ERROR: Couldn't create NSXMLParser object")
            _parser = NSXMLParser()
            super.init()
            
            return nil
        }
        
    }
    
    init(data: NSData){
        _parser = NSXMLParser(data: data)
        super.init()
        _parser.delegate = self
    }
    
    //MARK: PROPERTIES
    
    var rootElementº:XMLElement? {
        if (!_parsed){
            _parsed = _parser.parse()
        }
        
        return _rootElementº
    }
    
    var delegateº:XMLParserDelegate?
    
    func parse() -> Bool {
        if (!_parsed){
            _parsed = _parser.parse()
        }
        
        return _parsed
    }
    
    //MARK: NSXMLParserDelegate
    func parserDidStartDocument(parser: NSXMLParser) {
        self.delegateº?.parserDidStartDocument(self)
    }
    
    func parserDidEndDocument(parser: NSXMLParser) {
        self.delegateº?.parserDidEndDocument(self)
    }
    
    func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        
        if let _ = _currentElementº {
            _currentElementº = _currentElementº?.addChildElement(name: elementName, attributes: (attributeDict as [String:String]))
        } else {
            _rootElementº = XMLElement(name: elementName, attributes: (attributeDict as [String:String]))
            _currentElementº = _rootElementº
        }
        
        self.delegateº?.parser(self, didStartElement: _currentElementº!)
    }
    
    func parser(parser: NSXMLParser, foundCharacters string: String) {
        
        //remove '\t','\n', if the cleanString is not emptyString, then the value is found
        let cleanString:String = string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        if (cleanString != String()){
            _currentElementº?.valueº = cleanString
            self.delegateº?.parser(self, valueFoundInElement: _currentElementº!)
        }
    }
    
    func parser(parser: NSXMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        
        self.delegateº?.parser(self, didEndElement: _currentElementº!)
        _currentElementº = _currentElementº?.parentElementº
    }
}

internal class XMLWriter {
    
    private func _printNestingToString(inout targetString:String, nestingElement:XMLElement, nestlingLevel:UInt){
        
        //indends
        nestlingLevel.iterate { targetString += "\t" }
        
        //open-field
        targetString += "<\(nestingElement.name)"
        for (attributeName, attributeValue) in nestingElement.attributes {
            targetString += " \(attributeName)=\"\(attributeValue)\""
        }
        targetString += ">"
        
        if(nestingElement.childElements.count > 0){
            
            targetString += "\n"
            for childElement in nestingElement.childElements {
                _printNestingToString(&targetString, nestingElement: childElement, nestlingLevel: nestlingLevel+1)
            }
            
            if let elementValue = nestingElement.valueº {
                (nestlingLevel+1).iterate { targetString += "\t" }
                targetString += "\(elementValue)\n"
            }
            
            (nestlingLevel).iterate { targetString += "\t" }
            targetString += "</\(nestingElement.name)>"
            
        } else if let elementValue = nestingElement.valueº {
            targetString += "\(elementValue)</\(nestingElement.name)>"
        } else {
            targetString += "</\(nestingElement.name)>"
        }
        
        targetString += "\n"
    }
    
    init(rootElement:XMLElement){
        self.rootElement = rootElement
    }
    
    //MARK: PROPERTIES
    
    var rootElement:XMLElement
    
    var representativeString:String {
        
        var xmlString = String()
        
        xmlString += "\(xmlDeclaration)\n"
        _printNestingToString(&xmlString, nestingElement:self.rootElement, nestlingLevel: 0)
        
        return xmlString
    }
    
    var dataº:NSData? {
        return self.representativeString.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
    }

}
