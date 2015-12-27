//
//  UPNPArgument.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 11/8/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

//typealises to differentiate arguments and actions that are used in device description
//and the one used for invocation of actions
public typealias UPNPInvocationArgument = UPNPArgument

public class UPNPArgument {
    
    public let name: String
    public let isDirectionIn: Bool
    public let relatedStateVariableName: String
    public var relatedStateVariableº:UPNPStateVariable?
    
    //optional
    public let isReturnValueArgument: Bool
    
    //constant because you are not supposed to change it once obj is initialized
    //initialize new instance instead
    public let associatedValueº:String?
    
    init(xmlElement: XMLElement) throws {
        
        guard let name = xmlElement.childElement(name: "name")?.valueº,
              let directionString = xmlElement.childElement(name: "direction")?.valueº,
              let relatedStateVariableName = xmlElement.childElement(name: "relatedStateVariable")?.valueº
        else {
            self.name = String(); self.isDirectionIn = false; self.relatedStateVariableName = String();
            self.isReturnValueArgument = false; self.associatedValueº = nil
            throw UPNPComponentError.XMLElementDoesntContainRequiredChildElement
        }
        
        self.name = name
        self.relatedStateVariableName = relatedStateVariableName
        
        if(directionString == "in"){
            self.isDirectionIn = true
        } else {
            self.isDirectionIn = false
        }
        
        if (xmlElement.childElement(name: "retval") != nil){
            self.isReturnValueArgument = true
        } else {
            self.isReturnValueArgument = false
        }

        self.associatedValueº = nil
    }
    
    //initializer for action invocation
    public init(associatedArgument: UPNPArgument, value: String){
        
        self.name = associatedArgument.name
        self.isDirectionIn = associatedArgument.isDirectionIn
        self.relatedStateVariableName = associatedArgument.relatedStateVariableName
        self.relatedStateVariableº = associatedArgument.relatedStateVariableº
        self.isReturnValueArgument = associatedArgument.isReturnValueArgument
        self.associatedValueº = value
    }

}