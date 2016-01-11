//
//  SSDPServer.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 4/10/15.
//  reviewed on 9/3/15 by ambientlight.
//
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

let SSDPDefaultMulticastAddressString:String = "239.255.255.250"
let SSDPDefaultPort:in_port_t = 1900
let SSDPMulticastAddress:sockaddr_in = sockaddr_in(sin_len: __uint8_t(strideof(sockaddr_in)), sin_family: sa_family_t(AF_INET), sin_port: htons(SSDPDefaultPort), sin_addr: in_addr(s_addr: inet_addr(SSDPDefaultMulticastAddressString)), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))


let SSDPDefaultReadSize:UInt = 1024
private let _readMulticastQueueLabel = "com.ambientlight.ssdp-server.read-multicast-queue"
private let _unicastQueueLabel = "com.ambientlight.ssdp-server.unicast-queue"

let SSDPDefaultInitialDiscoveryCount:UInt = 5
let SSDPDefaultInitialDiscoveryInterval:UInt = 2000 //millisec.

let SSDPUnicastDiscoveryCount:UInt = 3
let SSDPUnicastDiscoveryInterval:UInt = 250 //millisec.

let SSDPDefaultMX: UInt = 1

//MARK: Protocol - SSDPServerDelegate
internal protocol SSDPServerDelegate {
    
    // please note that those methods will be called on the masterQueue of the delegate object
    func onEntityAliveMessage(ssdpMessage: SSDPMessage)
    func onEntityUpdateMessage(ssdpMessage: SSDPMessage)
    func onEntityByebyeMessage(ssdpMessage: SSDPMessage)
    
    // entity implies Device or Service
    
    var masterQueue:dispatch_queue_t { get }
}

//MARK:
public class SSDPServer {
    
    //MARK: public: Properties
    public private(set) var readMulticastSocket:SocketFD = -1
    public private(set) var unicastSocket:SocketFD = -1
    public private(set) var isRunning = false
    
    public var readMulticastSourceCancelCompletionHandlerº:(() -> Void)?
    public var unicastSourceCancelCompletionHandlerº:(() -> Void)?
    
    public var containsActiveTimers:Bool { return (_timerArray.count > 0) }
    
    internal var delegateº:SSDPServerDelegate?
    
    
    //MARK: private: Properties
    private let _readMulticastQueue:dispatch_queue_t = dispatch_queue_create(_readMulticastQueueLabel, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    private let _unicastQueue:dispatch_queue_t = dispatch_queue_create(_unicastQueueLabel, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0))
    
    private var _readMulticastSourceº:dispatch_source_t?
    private var _unicastSourceº:dispatch_source_t?
    //// timer-related things for repeated discovery messaging
    private var _timerArray:Array<DispatchTimer> = [DispatchTimer]()
    // gracefull shutdown requires all timers properly canceled
    private var _timersDisposedHandlerº:(()->Void)?
    
    
    
    //MARK: public: Methinits
    internal init() {}
    
    public func start() throws
    {
        if (self.isRunning) { return; }
        
        
        //multicast socket for listening to NOTIFY
        self.readMulticastSocket = try SocketPosix.initMulticastUDPSocket(SSDPDefaultPort, multicastAddress: SSDPMulticastAddress)
        let readMulticastSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(readMulticastSocket), 0, _readMulticastQueue)
        
        dispatch_source_set_event_handler(readMulticastSource) {
            
            do {
                
                let (data, senderAddress) = try SocketPosix.recvData(self.readMulticastSocket, readSize: SSDPDefaultReadSize)
                let message = try SSDPMessage.messageWithDataAndAddress(data, senderAddress: senderAddress)
                //print("\(message)\n")
                self._processMessage(message)
                
            } catch {
                print(error)
            }
        }
        
        dispatch_source_set_cancel_handler(readMulticastSource) {
            //close incoming socket
            do {
                try SocketPosix.optionLeaveMulticastGroup(self.readMulticastSocket, multicastAddress: inet_addr(SSDPDefaultMulticastAddressString))
                SocketPosix.release(self.readMulticastSocket)
                self._readMulticastSourceº = nil
                self.readMulticastSourceCancelCompletionHandlerº?()
                self.readMulticastSourceCancelCompletionHandlerº = nil
            } catch {
                print(error)
            }
        }
        
        dispatch_resume(readMulticastSource)
        _readMulticastSourceº = readMulticastSource

        
        //unicast socket for sending M-SEARCH, receiving M-SEARCH responses
        self.unicastSocket = try SocketPosix.initPlainUPDSocket()
        let unicastSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(unicastSocket), 0, _unicastQueue)
        
        dispatch_source_set_event_handler(unicastSource) {
            //data available to read
            
            do {
                let (data, senderAddress) = try SocketPosix.recvData(self.unicastSocket, readSize: SSDPDefaultReadSize)
                let message = try SSDPMessage.messageWithDataAndAddress(data, senderAddress: senderAddress)
                //print("\(message)\n")
                self._processMessage(message)
                
            } catch {
                print(error)
            }
        }
        
        dispatch_source_set_cancel_handler(unicastSource) {
            //close incoming socket
            SocketPosix.release(self.unicastSocket)
            self._unicastSourceº = nil
            self.unicastSourceCancelCompletionHandlerº?()
            self.unicastSourceCancelCompletionHandlerº = nil
        }
        
        dispatch_resume(unicastSource)
        _unicastSourceº = unicastSource
        
        
        self.isRunning = true;
        //send couple M-SEARCH discovery messages for initial discovery
        self.sendMulticastSearchRequest()
    }
    
    public func sendUnicastSearchRequestToAddress(  address: sockaddr_in,
                                               searchTarget: String = SSDPSearchTargetAll,
                                                repeatCount: UInt = SSDPUnicastDiscoveryCount,
                                             repeatInterval: UInt = SSDPUnicastDiscoveryInterval)
    {
        if(!isRunning){ return }
        
        
        var hostAddress = address
        hostAddress.sin_port = htons(SSDPDefaultPort)
        let discoverySSDPMessage = SSDPMessage.searchMessageWithSearchTarget(searchTarget, responseMaxWaitTime: 0, unicastAddressº: hostAddress)
        
        let resendTimer = DispatchTimer.scheduledTimerWithTimeInterval(milliseconds: repeatInterval, startOffset: -Int(repeatInterval), tolerance: 0, queue: _unicastQueue, isFinite: true, fireCount: repeatCount, userInfoº: nil, completionHandlerº: { (timer:DispatchTimer) in self._disposeTimer(timer) }) {
            (timer:DispatchTimer) in
            
            do {
                try SocketPosix.sendData(self.unicastSocket, toAddress: hostAddress, data: discoverySSDPMessage.data)
            } catch {
                print(error)
            }
        }
        
        _includeTimer(resendTimer)
    }
    
    
    
    public func sendMulticastSearchRequest(searchTarget: String = SSDPSearchTargetAll,
                                    responseMaxWaitTime: UInt = SSDPDefaultMX,
                                            repeatCount: UInt = SSDPDefaultInitialDiscoveryCount,
                                         repeatInterval: UInt = SSDPDefaultInitialDiscoveryInterval)
    {
        if(!isRunning){ return }
        
        
        let discoverySSDPMessage = SSDPMessage.searchMessageWithSearchTarget(searchTarget, responseMaxWaitTime: responseMaxWaitTime)
        
        let resendTimer = DispatchTimer.scheduledTimerWithTimeInterval(milliseconds: repeatInterval, startOffset: -Int(repeatInterval), tolerance: 0, queue: _readMulticastQueue, isFinite: true, fireCount: repeatCount, userInfoº: nil, completionHandlerº: { (timer:DispatchTimer) in self._disposeTimer(timer) }){
            (timer:DispatchTimer) in
            
            do {
                try SocketPosix.sendData(self.unicastSocket, toAddress: SSDPMulticastAddress, data: discoverySSDPMessage.data)
            } catch {
                print(error)
            }
        }
        
        _includeTimer(resendTimer)
    }
    
    
    
    // readMulticast ---> unicast ---> all timers ---> (suspention done)
    
    // suspention mechanism is a little tricky
    // we have 3 kinds of dispatch_sources we need to cancel: readMulticastSource, unicastSource and all active timers
    // so our cancelation is chained.
    // readMulticast..CompletionHandler will be called after dispatch_cancel_handler,
    // which will invoke cancel for unicast..CompletionHandler,
    // after which if we have active timers, we will start canceling them
    // Finally when the count of timers will drop to zero (in _disposeTimer()), cancelation is done
    
    public func stop(completionHandlerº:((Bool)->Void)? = nil){
        
        if(!isRunning){
            completionHandlerº?(true)
            return
        }
        
        readMulticastSourceCancelCompletionHandlerº = {
            //multicastSource canceled
            
            guard let unicastSource = self._unicastSourceº else {
                NSLog("\(self.dynamicType): \(__FUNCTION__): Unicast source is nil(which shouldn't be the case here).")
                
                defer { completionHandlerº?(false) }
                return
            }
            
            dispatch_source_cancel(unicastSource)
        }
        
        unicastSourceCancelCompletionHandlerº = {
            //unicastSource canceled
            
            if (self.containsActiveTimers){
                
                self._timersDisposedHandlerº = {
                    
                    self.isRunning = false
                    //timers disposed, cancelation done
                    
                    completionHandlerº?(true)
                    
                }
                
                self._cancelAllTimers()
                
            } else {
                
                self.isRunning = false
                //cancelation done
                
                completionHandlerº?(true)
                
            }
        }
        
        guard let readMulticastSource = _readMulticastSourceº else {
            NSLog("\(self.dynamicType): \(__FUNCTION__): ReadMulticast source is nil(which shouldn't be the case here).")
            
            defer { completionHandlerº?(false) }
            return
        }
        
        dispatch_source_cancel(readMulticastSource)
    }
    
    //MARK: private: Methods
    
    private func _includeTimer(timer:DispatchTimer){
        _timerArray.append(timer)
    }
    private func _disposeTimer(timer:DispatchTimer){
        
        _timerArray = _timerArray.filter {$0 != timer}
        
        if (_timerArray.count == 0){
            _timersDisposedHandlerº?()
            _timersDisposedHandlerº = nil
        }
    }
    
    
    private func _cancelAllTimers() {
        for timer:DispatchTimer in _timerArray {
            timer.invalidate()
        }
    }
    
    
    //invokes respectful delegate method
    private func _processMessage(message: SSDPMessage)
    {
        if let delegate = self.delegateº {
            
            guard let messageType = message.notificationSubtypeº else {
                NSLog("SSDPServer:_processMessage: Message notification subtype is not specified")
                return
            }
            
            switch(messageType) {
            case .alive:
                dispatch_async(delegate.masterQueue){ delegate.onEntityAliveMessage(message) }
            case .byebye:
                dispatch_async(delegate.masterQueue){ delegate.onEntityByebyeMessage(message) }
            case .update:
                dispatch_async(delegate.masterQueue){ delegate.onEntityUpdateMessage(message) }
            case .discover:
                //if there is anything you want to do with discovery messages
                break;
            }
            
            
        }
    }
}
