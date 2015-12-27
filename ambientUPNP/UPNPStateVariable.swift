//
//  UPNPStateVariable.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 11/8/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

public class UPNPStateVariable {
    
    public let name: String
    public let dataType: UPNPDataType
    public let defaultValue: String?
    public let allowedValueList: [String]
    private(set) public var allowedValueRange: UPNPValueRange?
    
    public let isEnumType: Bool
    public let sendEvents: Bool
    public let multicast: Bool
    
    public unowned let service: UPNPService
    
    // representative events should update 
    // (also updating on explicit action calls is not that redundant - in case eventing mechanism is dissabled or exibit problems)
    internal(set) var associatedValue:Any?
    
    
    init(xmlElement:XMLElement, associatedService:UPNPService) throws {
        
        self.service = associatedService
        
        var sendEvents = false
        var multicast = false
        
        if let sendEventsString = xmlElement.attributes["sendEvents"] {
            if let doesSendEvents = sendEventsString.toBool() {
                sendEvents = doesSendEvents
            }
        }
        
        if let multicastString = xmlElement.attributes["multicast"] {
            if let doesMulticasts = multicastString.toBool() {
                multicast = doesMulticasts
            }
        }
        
        self.sendEvents = sendEvents
        self.multicast = multicast
        
        guard let name = xmlElement.childElement(name: "name")?.valueº,
              let dataTypeString = xmlElement.childElement(name: "dataType")?.valueº
        else {
            self.name = String();
            self.dataType = UPNPDataType(extensionString: nil, type: .Unrecognized); self.defaultValue = nil
            self.allowedValueList = [String](); self.isEnumType = false;
            
            throw UPNPComponentError.XMLElementDoesntContainRequiredChildElement
        }
        
        self.name = name
        if let standartDataType = UPNPStandardDataType(rawValue: dataTypeString){
            self.dataType = UPNPDataType(extensionString: xmlElement.childElement(name: "dataType")?.attributes["type"], type: standartDataType)
        } else {
            self.dataType = UPNPDataType(extensionString: xmlElement.childElement(name: "dataType")?.attributes["type"], type: .Unrecognized)
        }
        
        self.defaultValue = xmlElement.childElement(name: "defaultElement")?.valueº
        if let allowedValueRangeElement = xmlElement.childElement(name: "allowedValueRange"){
            if let minimumValueString = allowedValueRangeElement.childElement(name: "minimum")?.valueº,
               let maximumValueString = allowedValueRangeElement.childElement(name: "maximum")?.valueº,
               let stepValueString = allowedValueRangeElement.childElement(name: "step")?.valueº{
                
                if let minimumValue = Double(minimumValueString),
                   let maximumValue = Double(maximumValueString),
                   let stepValue = Double(stepValueString){
                    
                    self.allowedValueRange = UPNPValueRange(minimum: minimumValue, maximum: maximumValue, step: stepValue)
                }
            }
            
            self.allowedValueList = [String]()
            self.isEnumType = false
            
        } else if let allowedValueListElement = xmlElement.childElement(name: "allowedValueList"){
            
            var allowedValueList = [String]()
            for allowedValueElement in allowedValueListElement.childElements {
                if let allowedValue = allowedValueElement.valueº {
                    allowedValueList.append(allowedValue)
                }
            }
            
            self.isEnumType = true
            self.allowedValueList = allowedValueList
            
        } else {
            self.isEnumType = false
            self.allowedValueList = [String]()
        }
        
    }
}

public struct UPNPValueRange {
    public let minimum: Double
    public let maximum: Double
    public let step: Double
}

public struct UPNPDataType {
    
    public let extensionString: String?
    public let type: UPNPStandardDataType
}

public enum UPNPStandardDataType: String, CustomStringConvertible {
    
    case TypeUI1 = "ui1"
    case TypeUI2 = "ui2"
    case TypeUI4 = "ui4"
    case TtypeI1 = "i1"
    case TypeI2 = "i2"
    case TypeI4 = "i4"
    case TypeInt = "int"
    case TypeR4 = "r4"
    case TypeR8 = "r8"
    case TypeNumber = "number"
    case TypeFixed_14_4 = "fixed.14.4"
    case TypeFloat = "float"
    case TypeChar = "char"
    case TypeString = "string"
    case TypeDate = "date"
    case TypeDateTime = "dateTime"
    case TypeDataTimeTz = "dataTime.tz"
    case TypeTime = "time"
    case TypeTimeTz = "time.tz"
    case TypeBoolean = "boolean"
    case TypeBinBase64 = "bin.base64"
    case TypeBinHex = "bin.hex"
    case TypeURI = "uri"
    case TypeUUID = "uuid"
    
    case Unrecognized = ""
    
    public var description:String {
        return self.rawValue
    }
}
