//
//  UPNPDevice.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 9/11/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

protocol UPNPDeviceDelegate {
    func deviceDidInitialize(device:UPNPDevice)
}

public class UPNPDevice:UPNPEntity {
    
    public enum InitError: ErrorType {
        case SpecVersionIsNotSpecified
        case NoDeviceElement
        case RequiredDeviceElementIsNotPresent
        case AliveMessageDoesntContainDeviceAddress
        case AliveMessageDoesntContainDescriptionURL
    }
    
    //MARK: PROPERTIES
    var delegateº:UPNPDeviceDelegate?
    
    private var _expirationHandleQueue:dispatch_queue_t = dispatch_queue_create("com.ambientlight.entity_expiration_queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    private var _expirationInitialMaxAgeº: UInt?
    
    private(set) public var embeddedDevices:Set<UPNPDevice> = Set<UPNPDevice>()
    private(set) public var services:Set<UPNPService> = Set<UPNPService>()
    
    private(set) public var partialServices:[UPNPServicePartialDescription] = [UPNPServicePartialDescription]()
    private(set) public var icons:[UPNPIconDescription] = [UPNPIconDescription]()
    
    public unowned let associatedControlPoint:UPNPControlPoint
    public let address:sockaddr_in
    public let isRootDevice:Bool
    
    public let deviceType:String
    public let friendlyName:String
    public let manufacturer:String
    public let modelName:String
    public let UDN:String
    
    private(set) public var manufacturerURL:NSURL?
    private(set) public var modelDescription:String?
    private(set) public var modelURL:NSURL?
    private(set) public var modelNumber:String?
    private(set) public var modelType:String?
    private(set) public var serialNumber:String?
    private(set) public var UPC:String?
    private(set) public var presentationURL:NSURL?
    
    public var universalUniqueIdentifier:String { return identifier }

    public var imageIcon:UIImage? {
        
        var icon:UIImage?
        var maxWidth:UInt = 0
        
        for iconDescription in self.icons {
            if let currentIcon = iconDescription.image {
                if iconDescription.width > maxWidth {
                    icon = currentIcon
                    maxWidth = iconDescription.width
                }
            }
        }
        
        return icon
    }
    
    public var hostURL:NSURL? {
        let components = NSURLComponents(URL: self.descriptionURL, resolvingAgainstBaseURL: false)
        components?.path = "/"
        return components?.URL
    }
    
    init(deviceXMLObject: XMLElement, isRootDevice:Bool, aliveMessage:SSDPMessage, associatedControlPoint:UPNPControlPoint) throws {
        
        self.isRootDevice = isRootDevice
        self.associatedControlPoint = associatedControlPoint
        
        guard let deviceAddress = aliveMessage.originatorAddress else {
            self.address = SocketPosix.LegacyStructInit()
            self.deviceType = String(); self.friendlyName = String(); self.manufacturer = String(); self.modelName = String(); self.UDN = String()
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))

            throw InitError.AliveMessageDoesntContainDeviceAddress
        }
        self.address = deviceAddress
        
        guard let deviceElement = deviceXMLObject.childElement(name: "device") else {
            self.deviceType = String(); self.friendlyName = String(); self.manufacturer = String(); self.modelName = String(); self.UDN = String()
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))

            throw InitError.NoDeviceElement
        }
        
        guard let deviceType = deviceElement.childElement(name: "deviceType")?.valueº,
              let friendlyName = deviceElement.childElement(name: "friendlyName")?.valueº,
              let manufacturer = deviceElement.childElement(name: "manufacturer")?.valueº,
              let modelName = deviceElement.childElement(name: "modelName")?.valueº,
              let UDN = deviceElement.childElement(name: "UDN")?.valueº
        else {
            self.deviceType = String(); self.friendlyName = String(); self.manufacturer = String(); self.modelName = String(); self.UDN = String()
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))

            throw InitError.RequiredDeviceElementIsNotPresent
        }
        
        if let manufacturerURLString = deviceElement.childElement(name: "manufacturerURL")?.valueº {
            self.manufacturerURL = NSURL(string: manufacturerURLString)
        }
        if let modelURLString = deviceElement.childElement(name: "modelURL")?.valueº {
            self.modelURL = NSURL(string: modelURLString)
        }
        if let presentationURLString = deviceElement.childElement(name: "presentationURL")?.valueº {
            self.presentationURL = NSURL(string: presentationURLString)
        }
        
        self.deviceType = deviceType
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        
        self.modelDescription = deviceElement.childElement(name: "modelDescription")?.valueº
        self.modelNumber = deviceElement.childElement(name: "modelNumber")?.valueº
        self.serialNumber = deviceElement.childElement(name: "serialNumber")?.valueº
        self.UDN = UDN
        self.UPC = deviceElement.childElement(name: "UPC")?.valueº
        self.modelType = deviceElement.childElement(name: "modelType")?.valueº
        
        guard let descriptionURL = aliveMessage.descriptionURLº else {
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))

            throw InitError.AliveMessageDoesntContainDescriptionURL
        }
        
        guard let specVersionElement = deviceXMLObject.childElement(name: "specVersion") else {
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))
            
            throw InitError.SpecVersionIsNotSpecified
        }
        
        do {
            let specVersion = try UPNPVersion(xmlElement: specVersionElement)
            super.init(identifier: self.UDN, descriptionURL: descriptionURL, specVersion: specVersion)
        } catch {
            super.init(identifier: String(), descriptionURL: NSURL(), specVersion: UPNPVersion(major: 0, minor: 0))
            throw error
        }
        
        if let deviceListElement = deviceElement.childElement(name: "deviceList"){
            for embeddedDeviceElement in deviceListElement.childElements(name: "device") {
                let newEmbeddedDevice = try UPNPDevice(deviceXMLObject: embeddedDeviceElement, isRootDevice: false, aliveMessage: aliveMessage, associatedControlPoint: associatedControlPoint)
                self.embeddedDevices.insert(newEmbeddedDevice)
            }
        }
        
        if let iconListElements = deviceElement.childElement(name: "iconList"){
            for iconElement in iconListElements.childElements(name: "icon"){
                var newIcon = try UPNPIconDescription(xmlElement: iconElement)
                
                let iconURL = self.hostURL!.URLByAppendingPathComponent(newIcon.urlRelativePath)
                if let imageData = NSData(contentsOfURL: iconURL){
                    newIcon.image = UIImage(data: imageData)
                }
                
                self.icons.append(newIcon)
            }
        }
        
        if let serviceListElements = deviceElement.childElement(name: "serviceList"){
            for partialServiceElement in serviceListElements.childElements(name: "service"){
                let newPartialService = try UPNPServicePartialDescription(xmlElement: partialServiceElement)
                self.partialServices.append(newPartialService)
            }
        }
        
        _expirationInitialMaxAgeº = aliveMessage.maxAgeº
        self.status = .PendingServiceInit
    }
    
    internal func addInitializedService(service:UPNPService){
        self.services.insert(service)
        
        if (self.services.count == self.partialServices.count){
            //device initialization fully done
            _setupExpiration()
            self.status = .Alive
            self.delegateº?.deviceDidInitialize(self)
        }
    }
    
    public func shutdown(){
        
        self.expirationTimer?.invalidate()
        for service:UPNPService in self.services {
            service.expirationTimer?.invalidate()
        }
    }
    
    //MARK: METHODS
    public func service(forType type: String) -> UPNPService? {
        guard let foundIndex = (self.services.indexOf { (service:UPNPService) in
            return (service.serviceType == type)
        }) else {
            return nil
        }
        
        return self.services[foundIndex]
    }
    
    private func _setupExpiration() {
        
        let expirationHandler: (DispatchTimer) -> Void = { (timer:DispatchTimer) in
            
            //handle expiration
            if let expiredDevice = timer.userInfoº as? UPNPDevice {
                NSLog("WARN: \(expiredDevice.friendlyName) has expired")
            } else if let expiredService = timer.userInfoº as? UPNPService {
                NSLog("WARN: \(self.friendlyName)::\(expiredService.serviceType) has expired")
            }
        }
        
        if let expirationIntervalSec = _expirationInitialMaxAgeº {
            self.expirationTimer = DispatchTimer.timerWithTimeInterval(milliseconds: expirationIntervalSec * 1000, queue: self._expirationHandleQueue, repeats: false, invocationBlock: expirationHandler)
            self.expirationTimer?.userInfoº = self
            
            for service in self.services {
                service.expirationTimer = DispatchTimer.timerWithTimeInterval(milliseconds: expirationIntervalSec * 1000, queue: self._expirationHandleQueue, repeats: false, invocationBlock: expirationHandler)
                service.expirationTimer?.userInfoº = service
                service.expirationTimer?.start()
            }
            
            self.expirationTimer?.start()
        } else {
            NSLog("\(self.dynamicType): \(__FUNCTION__): Couldn't setup expiration handler. MaxAge hasn't been set")
        }
        
    }

    
    func refreshExpiration(ssdpMessage: SSDPMessage) {
        
        var expirationIntervalSec:UInt = 0
        if let maxAge = ssdpMessage.maxAgeº {
            expirationIntervalSec = maxAge
        }
        
        if (expirationIntervalSec == 0) { return }
        
        let expirationHandler: (DispatchTimer) -> Void = { (timer:DispatchTimer) in
            
            //handle expiration
            if let expiredDevice = timer.userInfoº as? UPNPDevice {
                NSLog("WARN: \(expiredDevice.friendlyName) has expired")
            } else if let expiredService = timer.userInfoº as? UPNPService {
                NSLog("WARN: \(self.friendlyName)::\(expiredService.serviceType) has expired")
            }
        }
        
        if let messageUSN = ssdpMessage.uniqueServiceNameº {
            
            if let messageUUID = ssdpMessage.universallyUniqueIdentifierº {
                
                if messageUSN == messageUUID {
                    // device refresh advertisement (USN == UUID)
                    self.expirationTimer?.invalidate(){ (timer: DispatchTimer) in
                        
                        //NSLog("\(self.friendlyName) expiration has been refreshed.(\(expirationIntervalSec) sec)")
                        
                        self.expirationTimer = DispatchTimer.timerWithTimeInterval(milliseconds: expirationIntervalSec * 1000, queue: self._expirationHandleQueue, repeats: false, invocationBlock: expirationHandler)
                        self.expirationTimer?.userInfoº = self
                        self.expirationTimer?.start()
                    }
                    
                    
                } else if let messageEntityIdentifier = ssdpMessage.entityIdentifierº {
                    
                    if messageUUID == self.universalUniqueIdentifier {
                        // root device refresh advertisement (USN == UUID::upnp:rootdevice)
                        if messageEntityIdentifier == SSDPSearchTargetRootDevice && self.isRootDevice == true {
                            self.expirationTimer?.invalidate(){ (timer: DispatchTimer) in
                                
                                //NSLog("\(self.friendlyName) expiration has been refreshed.(\(expirationIntervalSec) sec)")
                                
                                self.expirationTimer = DispatchTimer.timerWithTimeInterval(milliseconds: expirationIntervalSec * 1000, queue: self._expirationHandleQueue, repeats: false, invocationBlock: expirationHandler)
                                self.expirationTimer?.userInfoº = self
                                self.expirationTimer?.start()
                            }
                        }
                        
                        // service refresh adveritisement (USN == UUID::serviceId)
                        if let service = self.service(forType:messageEntityIdentifier){
                            service.expirationTimer?.invalidate(){ (timer: DispatchTimer) in
                                
                                //NSLog("\(self.friendlyName)::\(service.serviceType) expiration has been refreshed.(\(expirationIntervalSec) sec)")
                                
                                service.expirationTimer = DispatchTimer.timerWithTimeInterval(milliseconds: expirationIntervalSec * 1000, queue: self._expirationHandleQueue, repeats: false, invocationBlock: expirationHandler)
                                service.expirationTimer?.userInfoº = service
                                service.expirationTimer?.start()
                            }
                        }
                        
                        //////
                    }
                }
            }
        }
        
        
    }

    
}