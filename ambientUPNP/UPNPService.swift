//
//  UPNPService.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 11/7/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

public protocol UPNPServiceDelegate {
    
    func serviceDidSubscribeForEventing(service: UPNPService)
    func serviceDidRecieveInitialEventNotification(service: UPNPService)
    func service(service: UPNPService, eventNotificationDidUpdateStateVariable stateVariable: UPNPStateVariable)
    
    func serviceDidResubscribeForEventing(service: UPNPService)
    func serviceDidUnsubscribeFromEventing(service: UPNPService)
    func serviceSubscriptionDidExpire(service: UPNPService)
    
    func service(service: UPNPService, didFailToSubscribeForEventingWithError error: ErrorType)
}

public class UPNPService: UPNPEntity {
    
    public enum InitError: ErrorType {
        case SpecVersionIsNotSpecified
        case DeviceHostURLNotPresent
        case RequiredServiceElementIsNotPresent
    }

    public var delegateº: UPNPServiceDelegate?
    
    private(set) public var actions:[UPNPAction] = [UPNPAction]()
    private(set) public var stateVariables:[UPNPStateVariable] = [UPNPStateVariable]()
    
    public let serviceType: String
    public var serviceId:String { return identifier }
    
    public var SCPDURL:NSURL { return descriptionURL }
    public let controlURL: NSURL
    public let eventSubURL: NSURL
    
    private(set) public var isSubscriptionActive: Bool = false
    private(set) public var didRecieveInitialEventNotification: Bool = false
    private(set) public var subscriptionIdentifierº: String?
    
    
    public unowned let device: UPNPDevice
    
    
    init(serviceXMLObject:XMLElement, partialServiceDescription:UPNPServicePartialDescription, associatedDevice:UPNPDevice, delegateº:UPNPServiceDelegate? = nil) throws {
        
        self.delegateº = delegateº
        
        self.device = associatedDevice
        self.serviceType = partialServiceDescription.serviceType
        
        guard let hostURL = associatedDevice.hostURL else {
            self.controlURL = NSURL(); self.eventSubURL = NSURL()
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))
            throw InitError.DeviceHostURLNotPresent
        }
        
        self.controlURL = hostURL.URLByAppendingPathComponent(partialServiceDescription.controlURLRelativePath)
        self.eventSubURL = hostURL.URLByAppendingPathComponent(partialServiceDescription.eventSubURLRelativePath)
        
        guard let specVersionElement = serviceXMLObject.childElement(name: "specVersion") else {
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))
            throw InitError.SpecVersionIsNotSpecified
        }
        
        do {
            let specVersion = try UPNPVersion(xmlElement: specVersionElement)
            super.init(identifier: partialServiceDescription.serviceId, descriptionURL: hostURL.URLByAppendingPathComponent(partialServiceDescription.SCPDURLRelativePath), specVersion: specVersion)
        } catch {
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))
            throw error
        }

        guard let actionListElement = serviceXMLObject.childElement(name: "actionList"),
              let stateVariableListElement = serviceXMLObject.childElement(name: "serviceStateTable")
        else {
            throw InitError.RequiredServiceElementIsNotPresent
        }
        
        for stateVariableElement in stateVariableListElement.childElements {
            let stateVariable = try UPNPStateVariable(xmlElement: stateVariableElement, associatedService: self)
            self.stateVariables.append(stateVariable)
        }
        
        for actionElement in actionListElement.childElements {
            let action = try UPNPAction(xmlElement: actionElement, associatedService: self)
            for (index, actionArgument) in action.arguments.enumerate() {
                if let foundIndex = (self.stateVariables.indexOf { return ($0.name == actionArgument.relatedStateVariableName) }){
                    action.arguments[index].relatedStateVariableº = self.stateVariables[foundIndex]
                }
            }
            
            self.actions.append(action)
        }
        
        self.status = .Alive
        
        self.device.associatedControlPoint.genaServer.subscribeToService(self) { (subscriptionIdentifierº:String?, errorº:ErrorType?) in
            if let error = errorº {
                self.delegateº?.service(self, didFailToSubscribeForEventingWithError: error)
            } else if let subscriptionIdentifier = subscriptionIdentifierº {
                
                self.subscriptionIdentifierº = subscriptionIdentifier
                self.isSubscriptionActive = true
                self.delegateº?.serviceDidSubscribeForEventing(self)
                
            } else {
                self.delegateº?.service(self, didFailToSubscribeForEventingWithError: GENAServer.Error.MessageDoesntContainSubscriptionIdentifier)
            }
        }
    }
    
    public func action(forName name:String) -> UPNPAction? {
        
        guard let foundIndex = (self.actions.indexOf { (action:UPNPAction) in
            return (action.name == name)
        }) else {
            return nil
        }
        
        return self.actions[foundIndex]
    }
    
    public func stateVariable(forName name:String) -> UPNPStateVariable? {
        
        guard let foundIndex = (self.stateVariables.indexOf { (stateVariable: UPNPStateVariable) in
            return (stateVariable.name == name)
        }) else {
            return nil
        }
        
        return self.stateVariables[foundIndex]
    }
    
    //MARK: internal: Eventing-related callbacks from GENAServer
    internal func handleEventWithMessage(eventMessage: GENAMessage) {
        
        for (updatedStateVariableName, (updatedValue, isUpdatedValueContainsXML)) in eventMessage.propertySet {
            
            if let stateVariableToUpdate = self.stateVariable(forName: updatedStateVariableName) where !isUpdatedValueContainsXML {
                stateVariableToUpdate.associatedValue = updatedValue
                self.delegateº?.service(self, eventNotificationDidUpdateStateVariable: stateVariableToUpdate)
                
            } else if let xmlBatchUpdateElement = updatedValue as? XMLElement {
                
                // batch xml updates such as 'LastChange' has to be handled properly in subclass ovverrides of this method
                NSLog("\(self.device.friendlyName):\(self.serviceType): did recieve batch update: \(updatedStateVariableName) = \(XMLSerialization.stringWithXMLObject(xmlBatchUpdateElement))")
            }
        }
        
        if (!self.didRecieveInitialEventNotification){
            self.didRecieveInitialEventNotification = true
            
            self.delegateº?.serviceDidRecieveInitialEventNotification(self)
        }
    }
    
    internal func subscriptionDidResubscribe(subscriptionIdentifier: String) {
        self.isSubscriptionActive = true
        
        // false since it will be sent again on resubscribe, and we should properly delegate it as well
        self.didRecieveInitialEventNotification = false
        self.subscriptionIdentifierº = subscriptionIdentifier
        
        self.delegateº?.serviceDidResubscribeForEventing(self)
    }
    
    internal func subscriptionDidUnsubscribe() {
        self.isSubscriptionActive = false
        self.subscriptionIdentifierº = nil
        self.didRecieveInitialEventNotification = false
        
        self.delegateº?.serviceDidUnsubscribeFromEventing(self)
    }
    
    internal func subscriptionDidExpire() {
        self.isSubscriptionActive = false
        self.subscriptionIdentifierº = nil
        self.didRecieveInitialEventNotification = false
        
        self.delegateº?.serviceSubscriptionDidExpire(self)
    }
}

extension UPNPService: Hashable {
    
    public var hashValue: Int {
        return "\(self.device.identifier):\(self.identifier)".hashValue
    }
}

//MARK: Equatable
public func ==(lhs: UPNPService, rhs: UPNPService) -> Bool {
    return ("\(lhs.device.identifier):\(lhs.identifier)" == "\(rhs.device.identifier):\(rhs.identifier)")
}