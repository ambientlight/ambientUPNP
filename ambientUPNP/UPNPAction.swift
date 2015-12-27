//
//  UPNPAction.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 11/8/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

//typealises to differentiate arguments and actions that are used in device description
//and the one used for invocation of actions
public typealias UPNPActionInvocation = UPNPAction

public class UPNPAction {
    
    public let name: String
    private(set) public var arguments: [UPNPArgument] = [UPNPArgument]()
    
    public unowned let service: UPNPService
    
    init(xmlElement:XMLElement, associatedService:UPNPService) throws {
        
        self.service = associatedService
        
        guard let name = xmlElement.childElement(name: "name")?.valueº,
              let argumentListElement = xmlElement.childElement(name: "argumentList")
        else {
            self.name = String()
            throw UPNPComponentError.XMLElementDoesntContainRequiredChildElement
        }
        
        self.name = name
        
        for argumentElement in argumentListElement.childElements {
            let argument = try UPNPArgument(xmlElement: argumentElement)
            self.arguments.append(argument)
        }
    }
    
    //initializer for action invocation
    public init(associatedAction:UPNPAction, invocationArguments: [UPNPInvocationArgument]){
        
        self.name = associatedAction.name
        self.service = associatedAction.service
        
        self.arguments = invocationArguments
    }
    
    public func invoke(invocationArguments: [UPNPInvocationArgument], completionHandler: ([UPNPInvocationArgument], ErrorType?) -> () ) {
        
        let actionInvocation = UPNPActionInvocation(associatedAction: self, invocationArguments: invocationArguments)
        let soapRequest = SOAPRequest(actionInvocation: actionInvocation)
        SOAPSession.asynchronousRequest(soapRequest) { (soapResponseº:SOAPResponse?, errorº:ErrorType?) in
            
            var outArguments = [UPNPInvocationArgument]()
            var outErrorº:ErrorType? = errorº
            
            defer {
                completionHandler(outArguments, outErrorº)
            }
            
            if let soapResponse = soapResponseº {
                
                if let errorCode = soapResponse.errorCodeº {
                    outErrorº = SOAPResponse.Error.SOAPResponseResponseError(errorCode: errorCode)
                } else {
                    
                    for argumentName in soapResponse.arguments.keys {
                        
                        if let argumentIndex = (self.arguments.indexOf { return ($0.name == argumentName) }){
                            if let argumentValue = soapResponse.arguments[argumentName] {
                                let outArgument = UPNPInvocationArgument(associatedArgument: self.arguments[argumentIndex], value: argumentValue)
                                outArguments.append(outArgument)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func argument(forName name:String) -> UPNPArgument? {
        guard let foundIndex = (self.arguments.indexOf { (argument:UPNPArgument) in
            return (argument.name == name)
        }) else {
            return nil
        }
        
        return self.arguments[foundIndex]
    }
    
    public func argument(forRelatedStateVariableName relatedStateVariableName:String) -> UPNPArgument? {
        guard let foundIndex = (self.arguments.indexOf { (argument:UPNPArgument) in
            return (argument.relatedStateVariableName == relatedStateVariableName)
            }) else {
                return nil
        }
        
        return self.arguments[foundIndex]
    }
    
    
}