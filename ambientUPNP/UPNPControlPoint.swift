//
//  UPNPControlPoint.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 4/14/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

private let _cpointQueueLabel = "com.ambientlight.controlpoint"
private let _deviceRetrievalLabel = "com.ambientlight.description-retrieval-queue"

private var _testConnection:NSURLConnection?

//MARK: PROTOCOL: UPNPControlPointDelegate

public protocol UPNPControlPointDelegate {
    
    func controlPoint(controlPoint:UPNPControlPoint, deviceAdded addedDevice:UPNPDevice)
    func controlPoint(controlPoint:UPNPControlPoint, deviceRemoved removedDevice:UPNPDevice)
    func controlPoint(controlPoint:UPNPControlPoint, deviceUpdated updatedDevice:UPNPDevice)
}


//MARK:
public class UPNPControlPoint: SSDPServerDelegate, UPNPDeviceDelegate, UPNPServiceDelegate {
   
    enum Error: ErrorType {
        case DataTaskError(NSError)
        case DataTaskNoResponse
        case DataTaskReturnedWithErrorStatus(statusCode: Int)
        case DataTaskNoDataResponse
    }
    
    private let _cpointQueue:dispatch_queue_t = dispatch_queue_create(_cpointQueueLabel, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    private let _descriptionRetrievalQueue = dispatch_queue_create(_deviceRetrievalLabel, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_BACKGROUND, 0))
    
    internal var masterQueue:dispatch_queue_t { return _cpointQueue }
    internal let descriptionRetrievalQueue:NSOperationQueue = NSOperationQueue()
    
    public private(set) var devices: Set<UPNPDevice> = Set<UPNPDevice>()
    public private(set) var uuidPendingDevices: Set<String> = Set<String>()
    public private(set) var pendingAdvertisements: [String : [SSDPMessage]] = [String : [SSDPMessage]]()
    public private(set) var ssdpServer:SSDPServer = SSDPServer()
    public private(set) var genaServer:GENAServer = GENAServer()
    
    public var delegate:UPNPControlPointDelegate?
    
    
    internal let urlSessionDataTaskAssesmentClosure:((NSData?, NSURLResponse?, NSError?) -> ErrorType?) = { (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
        
        if let error = errorº {
            return Error.DataTaskError(error)
        }
        
        guard let response = responseº as? NSHTTPURLResponse else {
            return Error.DataTaskNoDataResponse
        }
        
        if (response.statusCode != 200){
            return Error.DataTaskReturnedWithErrorStatus(statusCode: response.statusCode)
        }
        
        guard let data = dataº else {
            return Error.DataTaskNoDataResponse
        }
        
        return nil
    }
    
    private func _fetchServiceDescriptionsAndInitServices(device: UPNPDevice){
        
        guard let hostURL = device.hostURL else {
            NSLog("\(self.dynamicType): \(__FUNCTION__): ERROR retrieving device hostURL")
            return
        }
        
        for partialService in device.partialServices {
            let descriptionURL = hostURL.URLByAppendingPathComponent(partialService.SCPDURLRelativePath)
            
            let request = NSURLRequest(URL: descriptionURL)
            let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
            let session = NSURLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: self.descriptionRetrievalQueue)
            let serviceDescriptionDataTask = session.dataTaskWithRequest(request) { (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
                
                if let dataTaskError = self.urlSessionDataTaskAssesmentClosure(dataº, responseº, errorº){
                    NSLog("\(self.dynamicType): \(__FUNCTION__): \(dataTaskError)")
                    return
                }
                
                guard let xmlData = dataº else {
                    NSLog("\(self.dynamicType): \(__FUNCTION__): No description data in response")
                    return
                }
                
                guard let serviceXMLElement = XMLSerialization.XMLObjectWithDataº(xmlData) else {
                    NSLog("\(self.dynamicType): \(__FUNCTION__): Couldn't parse XML data")
                    return
                }

                do {
                    let newService = try UPNPService.init(serviceXMLObject: serviceXMLElement, partialServiceDescription: partialService, associatedDevice: device, delegateº: self)
                    device.addInitializedService(newService)
                } catch {
                    NSLog("\(error)")
                }
            }
            
            serviceDescriptionDataTask.resume()
        }
        
    }
    
    private func _fetchDeviceDescriptionAndCreateDevice(ssdpMessage: SSDPMessage)
    {
        guard let descriptionURL = ssdpMessage.descriptionURLº else {
            NSLog("\(self.dynamicType): \(__FUNCTION__): No description URL in advertizement")
            return
        }
        
        let request:NSURLRequest = NSURLRequest(URL: descriptionURL)
        
        if descriptionURL.absoluteString.containsString("udhisapi.dll"){
            //NSLog("Ignoring \(ssdpMessage.uniqueServiceName!)")
            return
        }

        let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: self.descriptionRetrievalQueue)
        
        let deviceDescriptionDataTask = session.dataTaskWithRequest(request) { (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
            
            if let dataTaskError = self.urlSessionDataTaskAssesmentClosure(dataº, responseº, errorº){
                NSLog("\(self.dynamicType): \(__FUNCTION__): \(dataTaskError)")
                return
            }
            
            guard let xmlData = dataº else {
                NSLog("\(self.dynamicType): \(__FUNCTION__): No description data in response")
                return
            }
            
            guard let deviceXMLElement = XMLSerialization.XMLObjectWithDataº(xmlData) else {
                NSLog("\(self.dynamicType): \(__FUNCTION__): Couldn't parse XML data")
                return
            }
            
            do {
                
                let device = try UPNPDevice(deviceXMLObject: deviceXMLElement, isRootDevice: true, aliveMessage: ssdpMessage, associatedControlPoint: self)
                device.delegateº = self
                self._fetchServiceDescriptionsAndInitServices(device)
                
            } catch {
                NSLog("\(error)")
            }
            
        }
    
        deviceDescriptionDataTask.resume()
    }
    

    private func _processPendingAdvertisementsForDevice(device: UPNPDevice) {
        
        if let pendingArray = pendingAdvertisements[device.universalUniqueIdentifier] {
            
            for advertisement:SSDPMessage in pendingArray {
                //NSLog("Pending \(device.friendlyName) expiration has been refreshed.(\(advertisement.maxAgeº!) sec)")
                device.refreshExpiration(advertisement)
            }
            
            pendingAdvertisements.removeValueForKey(device.universalUniqueIdentifier)
        }
    }
    

    //MARK: 
    
    public init(){
        ssdpServer.delegateº = self
    }
    
    //MARK: METHODS
    
    public func start() throws {
        
        var capturedErrorº:ErrorType?
        dispatch_sync(_cpointQueue){
            
            do {
                try self.ssdpServer.start()
                try self.genaServer.start()
            } catch {
                capturedErrorº = error
            }
        }
        
        if let capturedError = capturedErrorº {
            throw capturedError
        }
    }
    
    public func stop(completionHandler:(()->Void)?){
        dispatch_async(_cpointQueue){
            
            self.ssdpServer.stop {
                completionHandler?()
            }
            
        }
    }
    
    public func device(forDeviceUUID deviceUUID:String) -> UPNPDevice? {
        guard let foundIndex = (self.devices.indexOf { (device:UPNPDevice) in
            return (device.universalUniqueIdentifier == deviceUUID)
        }) else {
            return nil
        }
        
        return self.devices[foundIndex]
    }
    
    public func device(forFriendlyName friendlyName: String) -> UPNPDevice? {
        guard let foundIndex = (self.devices.indexOf { (device:UPNPDevice) in
            return (device.friendlyName == friendlyName)
        }) else {
            return nil
        }
        
        return self.devices[foundIndex]
    }
    
    
    //MARK: SSDPServerDelegate
    
    internal func onEntityAliveMessage(ssdpMessage: SSDPMessage) {
        
        if let deviceUUID = ssdpMessage.universallyUniqueIdentifierº {
            
            if let device = self.device(forDeviceUUID:deviceUUID) {
                // do stuff if device already exists
                
                device.refreshExpiration(ssdpMessage)
                
            } else if uuidPendingDevices.contains(deviceUUID) {
                
                //NSLog("Adding advertizement \(ssdpMessage.uniqueServiceNameº!) to pending list")
                
                // do stuff for pending devices, save advertisements
                if var pendingArray = pendingAdvertisements[deviceUUID] {
                    
                    pendingArray.append(ssdpMessage)
                    self.pendingAdvertisements.updateValue(pendingArray, forKey: deviceUUID)
                    
                } else {
                    
                    var pendingArray: [SSDPMessage] = [SSDPMessage]()
                    pendingArray.append(ssdpMessage)
                    self.pendingAdvertisements[deviceUUID] = pendingArray
                    
                }
                
            } else {
            
                // start parsing device description
                self.uuidPendingDevices.insert(deviceUUID)
                _fetchDeviceDescriptionAndCreateDevice(ssdpMessage)
            }
        }
    }
    
    
    internal func onEntityByebyeMessage(ssdpMessage: SSDPMessage) {
        
        if let deviceUUID = ssdpMessage.universallyUniqueIdentifierº {
            
            if let device = device(forDeviceUUID:deviceUUID) {
                device.shutdown()
                self.devices.remove(device)
                
                NSLog("\(device.friendlyName)[\(device.deviceType)] has been removed. (send byebye)")
                //self.delegate?.onDeviceRemove(self, removedDevice: device)
            }
        }
    }
    
    

    
    internal func onEntityUpdateMessage(ssdpMessage: SSDPMessage) {
        
        
        // handle entity update
    }
    
    
    //MARK: Delegate: UPNPDeviceDelegate
    
    func deviceDidInitialize(device: UPNPDevice) {
        
        NSLog("\(device.friendlyName) has been added.")
        self.uuidPendingDevices.remove(device.universalUniqueIdentifier)
        self.devices.insert(device)
        _processPendingAdvertisementsForDevice(device)
        
        _networkLampDeviceTests(device)
    }
    
    //MARK: Delegate: UPNPServiceDelegate
    
    public func service(service: UPNPService, eventNotificationDidUpdateStateVariable stateVariable: UPNPStateVariable) {
        if let associatedValue = stateVariable.associatedValue as? String {
            NSLog("\(service.serviceType): stateVariable did update: \(stateVariable.name) = \(associatedValue)")
        }
    }
    
    
    public func serviceDidSubscribeForEventing(service: UPNPService) {
        NSLog("\(service.serviceType) has subscribed for eventing")
    }
    
    public func service(service: UPNPService, didFailToSubscribeForEventingWithError error: ErrorType) {
        NSLog("\(service.serviceType) has failed to subscribe for eventing: \(error)")
    }

    public func serviceDidRecieveInitialEventNotification(service: UPNPService) {
        NSLog("\(service.serviceType) did receive initial event notification")
    }
    
    public func serviceDidResubscribeForEventing(service: UPNPService) {
        NSLog("\(service.serviceType) did resubscribe for eventing")
    }
    
    public func serviceDidUnsubscribeFromEventing(service: UPNPService) {
        NSLog("\(service.serviceType) did unsubscribe from eventing")
    }
    
    public func serviceSubscriptionDidExpire(service: UPNPService) {
        NSLog("\(service.serviceType) subscription did expire")
    }
    
    //MARK: Tests
    private func _networkLampDeviceTests(device:UPNPDevice){
        
        if (device.modelName == "Network Light Bulb"){
            
            if let switchPowerService = device.service(forType: "urn:schemas-upnp-org:service:SwitchPower:1"){
                if let setTargetAction = switchPowerService.action(forName: "SetTarget"){
                    //grabing the required argument and invoking action
                    if let targetArgument = setTargetAction.argument(forRelatedStateVariableName: "Target"){
                        
                        let newTargetValueArgument = UPNPInvocationArgument(associatedArgument: targetArgument, value: "1")
                        setTargetAction.invoke([newTargetValueArgument]) { (returnArguments:[UPNPInvocationArgument], errorº:ErrorType?) in
                            
                            if let error = errorº {
                                NSLog("\(self.dynamicType): \(__FUNCTION__): SetTarget action invocation failure: \(error)")
                            } else {
                                NSLog("\(device.friendlyName):[\(switchPowerService.serviceType)]:\(setTargetAction.name): Invocation succeeded")
                            }
                        }
                    }
                }
            }
        }
        
    }
    
    /*
    //NSURLConnection delegate
    public func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        println("did receive response")
    }
    
    public func connection(connection: NSURLConnection, didReceiveData data: NSData) {
        println("did receive data")
    }
    
    public func connection(connection: NSURLConnection, willCacheResponse cachedResponse: NSCachedURLResponse) -> NSCachedURLResponse? {
        return nil
    }
    
    public func connectionDidFinishLoading(connection: NSURLConnection) {
        println("did finish loading")
    }
    
    public func connection(connection: NSURLConnection, didFailWithError error: NSError) {
        println("did fail with error")
    }
    */
    
}