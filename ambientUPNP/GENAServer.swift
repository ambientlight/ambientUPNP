//
//  GENAServer.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 12/26/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import Foundation

let GENADefaultMulticastAddressString:String = "239.255.255.246"
let GENADefaultMulticastPort:in_port_t = 7900
let GENAMulticastAddress:sockaddr_in = sockaddr_in(sin_len: __uint8_t(strideof(sockaddr_in)), sin_family: sa_family_t(AF_INET), sin_port: htons(GENADefaultMulticastPort), sin_addr: in_addr(s_addr: inet_addr(GENADefaultMulticastAddressString)), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))

let GENAUnicastListeningAddress:sockaddr_in = sockaddr_in(sin_len: __uint8_t(strideof(sockaddr_in)), sin_family: sa_family_t(AF_INET), sin_port: htons(GENAUnicastListeningPort), sin_addr: in_addr(s_addr: htonl(INADDR_ANY) ), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
let GENAUnicastListeningPort:in_port_t = 14900

private let _multicastEventQueueLabel = "com.ambientlight.gena-server.multicast-queue"
private let _unicastEventQueueLabel = "com.ambientlight.gena-server.unicast-queue"

private let _subscriptionExpirationRefreshFraction = 0.8

public class GENAServer {
    
    public enum Error:ErrorType {
        case RequiredHeaderFieldIsNotPresentInResponse
        case NoResponse
        case TimeoutParsingFailure
        
        case NotSubscribedToService
        
        case MessageDoesntContainSubscriptionIdentifier
    }
    
    public private(set) var multicastEventSocket:SocketFD = -1
    public private(set) var incomingEventsListeningSocket:SocketFD = -1
    
    // [sid: persistentSocketDispatchSource]
    public private(set) var eventNotificationPersistentConnectionDispatchSources = [String: dispatch_source_t]()
    
    //subscriptionData: [subscriberService: (sid, expirationTimer, resubscriptionTimer)]
    public private(set) var subscribersData = [UPNPService: (String, DispatchTimer?, DispatchTimer?)]() {
        willSet {
            //NSLog("<previousSubscribersData>: \(subscribersData.count) sids")
            //NSLog("<newSubscribersData>: \(newValue.count) sids")
        }
    }
    public private(set) var isRunning = false
    
    
    public var multicastEventSourceCancelCompletionHandlerº:(() -> Void)?
    public var unicastSourceCancelCompletionHandlerº:(() -> Void)?
    
    private let _multicastEventQueue:dispatch_queue_t = dispatch_queue_create(_multicastEventQueueLabel, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    private let _unicastQueue:dispatch_queue_t = dispatch_queue_create(_unicastEventQueueLabel, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    private var _subscriptionHandlingQueue:dispatch_queue_t = dispatch_queue_create("com.ambientlight.gena-server.subscription-handling-queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    
    
    private var _multicastEventSourceº:dispatch_source_t?
    private var _unicastSourceº:dispatch_source_t?
    
    //MARK: public: Methinits
    public init() {}
    
    public func start() throws {
        
        if (self.isRunning) { return; }
        
        self.multicastEventSocket = try SocketPosix.initMulticastUDPSocket(GENADefaultMulticastPort, multicastAddress: GENAMulticastAddress)
        let multicastEventSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(self.multicastEventSocket), 0, _multicastEventQueue)
        
        dispatch_source_set_event_handler(multicastEventSource){
            
            do {
                
                let (data, senderAddress) = try SocketPosix.recvData(self.multicastEventSocket)
                let eventMessage = try GENAMessage.messageWithData(data, senderAddress: senderAddress)
                try self._handleMulticastEventMessage(eventMessage)
                
            } catch {
                print(error)
            }
        }
        
        dispatch_source_set_cancel_handler(multicastEventSource){
            
            do {
                try SocketPosix.optionLeaveMulticastGroup(self.multicastEventSocket, multicastAddress: inet_addr(GENADefaultMulticastAddressString))
            } catch {
                print(error)
            }
            
            SocketPosix.release(self.multicastEventSocket)
            self._multicastEventSourceº = nil
            self.multicastEventSourceCancelCompletionHandlerº?()
            self.multicastEventSourceCancelCompletionHandlerº = nil
        }
        
        dispatch_resume(multicastEventSource)
        _multicastEventSourceº = multicastEventSource
        
        
        //TCP unicast socket for recieving unit event notifications
        self.incomingEventsListeningSocket = try SocketPosix.initListeningTCPSocket(GENAUnicastListeningPort, address: GENAUnicastListeningAddress)
        let unicastSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(self.incomingEventsListeningSocket), 0, _unicastQueue)
        
        dispatch_source_set_event_handler(unicastSource){
            
            var publisherAddress:sockaddr = SocketPosix.LegacyStructInit()
            var publisherAddressLength = socklen_t(strideof(sockaddr_in))
            
            let publisherSocket = accept(self.incomingEventsListeningSocket, &publisherAddress, &publisherAddressLength)
            var needsToKeepPersistentConnection: Bool = false
            var eventSubscriptionIdentifierº: String?
            do {
                try SocketPosix.optionDisableSigpipe(publisherSocket)
                try SocketPosix.optionSetPacketTTL(publisherSocket, ttl: 2)
                
                let (data, senderAddress) = try SocketPosix.recvData(publisherSocket)
                //NSLog("<MESSAGE CONTENT>\n\(String(data: data, encoding: NSUTF8StringEncoding)!)\n<MESSAGE CONTENT END>\n")
                //NSLog("Response recieved")
                
                let eventMessage = try GENAMessage.messageWithData(data, senderAddress: senderAddress)
                eventSubscriptionIdentifierº = eventMessage.subscriptionIdentifierº
                needsToKeepPersistentConnection = try self._handleUnicastEventMessageAndNotifyIfConnectionShouldBeClosed(eventMessage, socket: publisherSocket)
                
            } catch {
                print(error)
            }
            
            SocketPosix.release(publisherSocket)
            return
            
            /*
            
            // setting up a dispatch_source for connected socket, or closing the connection
            if (needsToKeepPersistentConnection && eventSubscriptionIdentifierº != nil){
                
                
                //NSLog("Keep-alive: Connected \(SocketPosix.addressString(unsafeBitCast(publisherAddress, sockaddr_in.self))) with socket(\(publisherSocket)) for event notifications.")
                
                let publisherReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(publisherSocket), 0, self._unicastQueue)
                self.eventNotificationPersistentConnectionDispatchSources[eventSubscriptionIdentifierº!] = publisherReadSource
                dispatch_source_set_event_handler(publisherReadSource){
                    
                    do {
                        
                        let (data, senderAddress) = try SocketPosix.recvData(publisherSocket)
                        NSLog("<Keep-alive: MESSAGE CONTENT>\n\(String(data: data, encoding: NSUTF8StringEncoding)!)\n<Keep-alive: MESSAGE CONTENT END>\n")
                        
                        do {
                            let eventMessage = try GENAMessage.messageWithData(data, senderAddress: senderAddress)
                            needsToKeepPersistentConnection = try self._handleUnicastEventMessageAndNotifyIfConnectionShouldBeClosed(eventMessage, socket: publisherSocket)
                            if (!needsToKeepPersistentConnection){
                                dispatch_source_cancel(publisherReadSource)
                            }
                        } catch {
                            NSLog("Keep-alive: socket(\(publisherSocket)): \(error)")
                        }
                        
                    } catch {
                        
                        if case SocketPosix.Error.Terminated(/*let errno*/) = error {
                            //
                        } else {
                            NSLog("Keep-alive: socket(\(publisherSocket)): \(error). Socket closed.")
                        }
                        
                        dispatch_source_cancel(publisherReadSource)
                    }
                }
                
                dispatch_source_set_cancel_handler(publisherReadSource){
                    
                    SocketPosix.release(publisherSocket)
                    self.eventNotificationPersistentConnectionDispatchSources.removeValueForKey(eventSubscriptionIdentifierº!)
                    //call completionHandler to decrement cancel count
                }
                
                dispatch_resume(publisherReadSource)
                
            } else {
                SocketPosix.release(publisherSocket)
            }
            
            */
        }
        
        dispatch_resume(unicastSource)
        _unicastSourceº = unicastSource
        
        self.isRunning = true
    }
    
    public func subscribeToService(service: UPNPService, completionHandler:(subscriptionIdentifierº:String?, errorº:ErrorType?) -> Void) {
        
        let subscribeRequest = NSMutableURLRequest(URL: service.eventSubURL, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 30)
        subscribeRequest.HTTPMethod = GENAMessage.Method.SUBSCRIBE.rawValue
        
        var portº: Int?
        if let hostURL = service.device.hostURL {
            let urlComponents = NSURLComponents(URL: hostURL, resolvingAgainstBaseURL: false)
            portº = urlComponents?.port?.integerValue
        }
        
        var hostString = SocketPosix.addressString(service.device.address)
        if let port = portº {
            hostString += ":\(port)"
        }
        
        var interfaceAddressº:sockaddr_in?
        var errorº:ErrorType?
        do {
            interfaceAddressº = try SocketPosix.firstAvailableInterfaceAddress()
        } catch {
            errorº = error
        }
        
        guard let interfaceAddress = interfaceAddressº else {
            completionHandler(subscriptionIdentifierº: nil, errorº: errorº)
            return
        }
        
        let callbackURL = NSURL(string: "http://\(SocketPosix.addressString(interfaceAddress)):\(GENAUnicastListeningPort)/event/")
        subscribeRequest.setValue(hostString, forHTTPHeaderField: GENAMessage.HeaderField.Host.rawValue)
        subscribeRequest.setValue("<\(callbackURL!.absoluteString)>", forHTTPHeaderField: GENAMessage.HeaderField.Callback.rawValue)
        subscribeRequest.setValue(UPNPEventNotificationType, forHTTPHeaderField: GENAMessage.HeaderField.NT.rawValue)
        
        let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
        
        let dataTask:NSURLSessionDataTask = session.dataTaskWithRequest(subscribeRequest) { (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
            
            dispatch_async(self._subscriptionHandlingQueue){
                
                if let error = errorº {
                    completionHandler(subscriptionIdentifierº: nil, errorº: error)
                    return
                }
                
                if let response = responseº as? NSHTTPURLResponse {
                    guard let subscriptionIdentifier = response.allHeaderFields[GENAMessage.HeaderField.SID.rawValue] as? String,
                        let timeoutComponentsString = response.allHeaderFields[GENAMessage.HeaderField.Timeout.rawValue] as? String
                        else {
                            completionHandler(subscriptionIdentifierº: nil, errorº: Error.RequiredHeaderFieldIsNotPresentInResponse)
                            return
                    }
                    
                    if let _ = response.allHeaderFields[GENAMessage.HeaderField.Statevar.rawValue] as? String {
                        //do something with accepted statevar CSV
                    }
                    
                    guard let timeoutString = timeoutComponentsString.componentsSeparatedByString("-").last else {
                        completionHandler(subscriptionIdentifierº: nil, errorº: Error.TimeoutParsingFailure)
                        return
                    }
                    
                    // infinite subscription. No Expiration
                    if (timeoutString == "infinite"){
                        
                        self.subscribersData[service] = (subscriptionIdentifier, nil, nil)
                        
                        completionHandler(subscriptionIdentifierº: subscriptionIdentifier, errorº: nil)
                        return
                    }
                    
                    guard let subscriptionTimeout = UInt(timeoutString) else {
                        completionHandler(subscriptionIdentifierº: nil, errorº: Error.TimeoutParsingFailure)
                        return
                    }
                    
                    
                    let expirationTimer = DispatchTimer.scheduledTimerWithTimeInterval(milliseconds: subscriptionTimeout * 1000, queue: self._subscriptionHandlingQueue, repeats: false) { (timer: DispatchTimer) in
                        
                        self.subscribersData.removeValueForKey(service)
                        if let persistentConnectionSource = self.eventNotificationPersistentConnectionDispatchSources[subscriptionIdentifier] {
                            dispatch_source_cancel(persistentConnectionSource)
                        }
                        
                        service.subscriptionDidExpire()
                    }
                    
                    let resubscriptionMilliseconds = UInt(Double(subscriptionTimeout) * _subscriptionExpirationRefreshFraction * 1000)
                    let resubscriptionTimer = DispatchTimer.scheduledTimerWithTimeInterval(milliseconds: resubscriptionMilliseconds, queue: self._subscriptionHandlingQueue, repeats: false) { (timer:DispatchTimer) in
                        
                        if (expirationTimer.valid){
                            expirationTimer.invalidate() { (timer:DispatchTimer) in }
                        }
                        
                        self.resubscribeToService(service) { (subscriptionIdentifierº:String?, errorº:ErrorType?) in
                            
                            //delegate error callback
                        }
                    }
                    
                    self.subscribersData[service] = (subscriptionIdentifier, expirationTimer, resubscriptionTimer)
                    completionHandler(subscriptionIdentifierº: subscriptionIdentifier, errorº: nil)
                    
                } else {
                    completionHandler(subscriptionIdentifierº: nil, errorº: Error.NoResponse)
                }

                
            }
        }
        
        dataTask.resume()
    }
    
    public func resubscribeToService(service:UPNPService, completionHandler:(subscriptionIdentifierº:String?, errorº:ErrorType?) -> Void){
        
        dispatch_async(self._subscriptionHandlingQueue){
            
            guard let (currentSubscriptionSID, currentExpirationTimerº, currentResubscriptionTimerº) = self.subscribersData[service] else {
                completionHandler(subscriptionIdentifierº: nil, errorº: Error.NotSubscribedToService)
                return
            }
            
            let subscribeRequest = NSMutableURLRequest(URL: service.eventSubURL, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 30)
            subscribeRequest.HTTPMethod = GENAMessage.Method.SUBSCRIBE.rawValue
            
            var portº: Int?
            if let hostURL = service.device.hostURL {
                let urlComponents = NSURLComponents(URL: hostURL, resolvingAgainstBaseURL: false)
                portº = urlComponents?.port?.integerValue
            }
            
            var hostString = SocketPosix.addressString(service.device.address)
            if let port = portº {
                hostString += ":\(port)"
            }
            
            subscribeRequest.setValue(hostString, forHTTPHeaderField: GENAMessage.HeaderField.Host.rawValue)
            subscribeRequest.setValue(currentSubscriptionSID, forHTTPHeaderField: GENAMessage.HeaderField.SID.rawValue)
            
            let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
            let session = NSURLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
            
            let dataTask:NSURLSessionDataTask = session.dataTaskWithRequest(subscribeRequest) { (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
                
                dispatch_async(self._subscriptionHandlingQueue){
                    
                    if let error = errorº {
                        completionHandler(subscriptionIdentifierº: nil, errorº: error)
                        return
                    }
                    
                    if let response = responseº as? NSHTTPURLResponse {
                        
                        guard let subscriptionIdentifier = response.allHeaderFields[GENAMessage.HeaderField.SID.rawValue] as? String,
                            let timeoutComponentsString = response.allHeaderFields[GENAMessage.HeaderField.Timeout.rawValue] as? String
                            else {
                                completionHandler(subscriptionIdentifierº: nil, errorº: Error.RequiredHeaderFieldIsNotPresentInResponse)
                                return
                        }
                        
                        if let _ = response.allHeaderFields[GENAMessage.HeaderField.Statevar.rawValue] as? String {
                            //do something with accepted statevar CSV
                        }
                        
                        guard let timeoutString = timeoutComponentsString.componentsSeparatedByString("-").last else {
                            completionHandler(subscriptionIdentifierº: nil, errorº: Error.TimeoutParsingFailure)
                            return
                        }
                        
                        // infinite subscription. No Expiration
                        if (timeoutString == "infinite"){
                            self.subscribersData[service] = (subscriptionIdentifier, nil, nil)
                            completionHandler(subscriptionIdentifierº: subscriptionIdentifier, errorº: nil)
                            return
                        }
                        
                        guard let subscriptionTimeout = UInt(timeoutString) else {
                            completionHandler(subscriptionIdentifierº: nil, errorº: Error.TimeoutParsingFailure)
                            return
                        }
                        
                        if let currentExpirationTimer = currentExpirationTimerº where currentExpirationTimer.valid {
                            currentExpirationTimer.invalidate { (timer:DispatchTimer) in }
                        }
                        if let currentResubscriptionTimer = currentResubscriptionTimerº where currentResubscriptionTimer.valid {
                            currentResubscriptionTimer.invalidate() { (timer:DispatchTimer) in }
                        }
                        
                        
                        let expirationTimer = DispatchTimer.scheduledTimerWithTimeInterval(milliseconds: subscriptionTimeout * 1000, queue: self._subscriptionHandlingQueue, repeats: false) { (timer: DispatchTimer) in
                            
                            self.subscribersData.removeValueForKey(service)
                            if let persistentConnectionSource = self.eventNotificationPersistentConnectionDispatchSources[subscriptionIdentifier] {
                                dispatch_source_cancel(persistentConnectionSource)
                            }
                            
                            service.subscriptionDidExpire()
                        }
                        
                        let resubscriptionMilliseconds = UInt(Double(subscriptionTimeout) * _subscriptionExpirationRefreshFraction * 1000)
                        let resubscriptionTimer = DispatchTimer.scheduledTimerWithTimeInterval(milliseconds: resubscriptionMilliseconds, queue: self._subscriptionHandlingQueue, repeats: false) { (timer:DispatchTimer) in
                            
                            if (expirationTimer.valid){
                                expirationTimer.invalidate() { (timer:DispatchTimer) in }
                            }
                            
                            self.resubscribeToService(service) { (subscriptionIdentifierº:String?, errorº:ErrorType?) in
                                
                                //delegate error callback
                            }
                        }
                        
                        self.subscribersData[service] = (subscriptionIdentifier, expirationTimer, resubscriptionTimer)
                        
                        service.subscriptionDidResubscribe(subscriptionIdentifier)
                        completionHandler(subscriptionIdentifierº: subscriptionIdentifier, errorº: nil)
                        
                    } else {
                        completionHandler(subscriptionIdentifierº: nil, errorº: Error.NoResponse)
                    }
                    
                }
                
            }
            
            dataTask.resume()
        }
    }
    
    public func unsubscribeFromService(service:UPNPService, completionHandler:(errorº:ErrorType?) -> Void){
        
        dispatch_async(_subscriptionHandlingQueue){
            
            guard let (currentSubscriptionSID, currentExpirationTimerº, currentResubscriptionTimerº) = self.subscribersData[service] else {
                completionHandler(errorº: Error.NotSubscribedToService)
                return
            }
            
            let unsubscribeRequest = NSMutableURLRequest(URL: service.eventSubURL, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 30)
            unsubscribeRequest.HTTPMethod = GENAMessage.Method.UNSUBSCRIBE.rawValue
            
            var portº: Int?
            if let hostURL = service.device.hostURL {
                let urlComponents = NSURLComponents(URL: hostURL, resolvingAgainstBaseURL: false)
                portº = urlComponents?.port?.integerValue
            }
            
            var hostString = SocketPosix.addressString(service.device.address)
            if let port = portº {
                hostString += ":\(port)"
            }
            
            unsubscribeRequest.setValue(hostString, forHTTPHeaderField: GENAMessage.HeaderField.Host.rawValue)
            unsubscribeRequest.setValue(currentSubscriptionSID, forHTTPHeaderField: GENAMessage.HeaderField.SID.rawValue)
            
            let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
            let session = NSURLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
            
            let dataTask:NSURLSessionDataTask = session.dataTaskWithRequest(unsubscribeRequest) { (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
                
                dispatch_async(self._subscriptionHandlingQueue){
                    
                    if let error = errorº {
                        completionHandler(errorº: error)
                    } else {
                        
                        if let currentExpirationTimer = currentExpirationTimerº where currentExpirationTimer.valid {
                            currentExpirationTimer.invalidate { (timer:DispatchTimer) in }
                        }
                        if let currentResubscriptionTimer = currentResubscriptionTimerº where currentResubscriptionTimer.valid {
                            currentResubscriptionTimer.invalidate() { (timer:DispatchTimer) in }
                        }
                        
                        self.subscribersData.removeValueForKey(service)
                        if let persistentConnectionSource = self.eventNotificationPersistentConnectionDispatchSources[currentSubscriptionSID] {
                            dispatch_source_cancel(persistentConnectionSource)
                        }
                        
                        service.subscriptionDidUnsubscribe()
                        completionHandler(errorº: nil)
                    }
                }
                
            }
            
            dataTask.resume()
        }
    }
    
    //MARK: private: Methods
    
    private func _handleUnicastEventMessageAndNotifyIfConnectionShouldBeClosed(eventMessage: GENAMessage, socket: SocketFD) throws -> Bool {
        
        // delegate eventUpdateCallback
        
        guard let messageSubscriptionIdentifier = eventMessage.subscriptionIdentifierº else {
            throw Error.MessageDoesntContainSubscriptionIdentifier
        }
        
        dispatch_sync(_subscriptionHandlingQueue){
            
            var didFindSubscriptionIdentifier: Bool = false
            for (service, (subscriptionIdentifier, _, _)) in self.subscribersData {
                if (subscriptionIdentifier == messageSubscriptionIdentifier){
                    service.handleEventWithMessage(eventMessage)
                    didFindSubscriptionIdentifier = true
                    break;
                }
            }
            
            if !didFindSubscriptionIdentifier {
                //NSLog("WARN: Subscription idenifier \(messageSubscriptionIdentifier) doesn't match the current subscriber list.")
            }
        }
        
        // send response
        if let responseOKData = GENAMessage.httpResponseOKData() {
            try SocketPosix.writeData(socket, data: responseOKData)
        }
        
        // deciding if we need to keep the connection or closing socket otherwise
        var needsToKeepPersistentConnection = true
        if (eventMessage.httpVersion == UPNPVersion(major: 1, minor: 0)){
            
            if (eventMessage.headers[GENAMessage.HeaderField.Connection]?.lowercaseString != "keep-alive"){
                needsToKeepPersistentConnection = false
            }
            
        } else if (eventMessage.httpVersion == UPNPVersion(major: 1, minor: 1)) {
            
            if (eventMessage.headers[GENAMessage.HeaderField.Connection]?.lowercaseString == "close"){
                needsToKeepPersistentConnection = false
            }
            
        } else {
            needsToKeepPersistentConnection = false
        }

        return needsToKeepPersistentConnection
    }
    
    private func _handleMulticastEventMessage(eventMessage: GENAMessage) throws {
        
        // delegate eventUpdateCallback
        guard let messageSubscriptionIdentifier = eventMessage.subscriptionIdentifierº else {
            throw Error.MessageDoesntContainSubscriptionIdentifier
        }
        
        dispatch_async(_subscriptionHandlingQueue){
            
            var didFindSubscriptionIdentifier: Bool = false
            for (service, (subscriptionIdentifier, _, _)) in self.subscribersData {
                if (subscriptionIdentifier == messageSubscriptionIdentifier){
                    service.handleEventWithMessage(eventMessage)
                    didFindSubscriptionIdentifier = true
                    break;
                }
            }
            
            if !didFindSubscriptionIdentifier {
                //NSLog("WARN: Subscription idenifier \(messageSubscriptionIdentifier) doesn't match the current subscriber list.")
            }
        }
    }
    
}