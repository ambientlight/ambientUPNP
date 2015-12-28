//
//  SocketPosix.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 3/28/15.
//  reviewed on 9/3/15 by ambientlight.
//
//  Copyright (c) 2015 ambientlight. All rights reserved.
//


import Foundation

let INADDR_ANY:__uint32_t = 0x00000000
let SOCK_LISTEN_QUEUE_MAX: Int32 = 1024

let SockListenPortDefault: UInt16 = 8080
let SockListenAcceptTimeout: Int32 = 1000 //milliseconds
let SockRecieveTimeout:Int32 = 2000 //milliseconds

let SockReadSize: UInt = 4096

//sockopt
let SockoptRecieveTimeoutSec: Int = 2
let SockoptRecieveTimeoutMicroSec: Int32 = 0

let SockoptSendTimeoutSec: Int = 0
let SockoptSendTimeoutMicroSec: Int32 = 0


public typealias SocketFD = CInt

public struct SocketPosix
{
    public enum Error:ErrorType {
        case SocketInitFailed(Int32)
        case CannotBindSocket(Int32)
        case ListenError(Int32)
        
        case Terminated
        
        case ReadError(Int32)
        case SendError(Int32)
        case SetSockoptError(Int32)
        
        case CannotProvideValidAvailableInterfaceAddress
    }
    
    //MARK: public: Methods
    
    public static func initMulticastUDPSocket(port: in_port_t, multicastAddress: sockaddr_in) throws -> SocketFD {
        
        let multicastSocket:SocketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (multicastSocket < 0) {
            throw SocketPosix.Error.SocketInitFailed(errno)
        }
        
        let address:sockaddr_in = multicastAddress
        try optionEnableAddressReuse(multicastSocket)
        try optionDisableSigpipe(multicastSocket)
        try optionJoinMulticastGroup(multicastSocket, multicastAddress: address.sin_addr.s_addr)
        
        var sAddress:sockaddr = unsafeBitCast(address, sockaddr.self)
        if (bind(multicastSocket, &sAddress, socklen_t(strideof(sockaddr_in))) < 0){
            release(multicastSocket)
            throw SocketPosix.Error.CannotBindSocket(errno)
        }
        
        return multicastSocket
    }
    
    public static func initPlainUPDSocket() throws -> SocketFD {
        
        let incomeSocket:SocketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (incomeSocket < 0) {
            throw SocketPosix.Error.SocketInitFailed(errno)
        }
        
        try optionEnableAddressReuse(incomeSocket)
        try optionDisableSigpipe(incomeSocket)
        //try optionDisableMulticastLoopback(incomeSocket)
        try optionSetPacketTTL(incomeSocket, ttl: 2)
        
        return incomeSocket
    }
    
    public static func initListeningTCPSocket(port: in_port_t, address: sockaddr_in) throws -> SocketFD {
        
        let streamSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if (streamSocket < 0) {
            throw SocketPosix.Error.SocketInitFailed(errno)
        }
        
        try optionEnableAddressReuse(streamSocket)
        try optionDisableSigpipe(streamSocket)
        try optionSetPacketTTL(streamSocket, ttl: 2)
        
        var addressToBind = address
        addressToBind.sin_port = htons(port)
        var sAddress:sockaddr = unsafeBitCast(addressToBind, sockaddr.self)
        if (bind(streamSocket, &sAddress, socklen_t(strideof(sockaddr_in))) < 0){
            release(streamSocket)
            throw SocketPosix.Error.CannotBindSocket(errno)
        }
        
        if (listen(streamSocket, SOCK_LISTEN_QUEUE_MAX) < 0){
            release(streamSocket)
            throw SocketPosix.Error.ListenError(errno)
        }
        
        return streamSocket
    }
    
    public static func release(socket: SocketFD) {
        shutdown(socket, SHUT_RDWR)
        close(socket)
    }
    
    public static func readData(socket: SocketFD, readSize: UInt = SockReadSize) throws -> NSData {
        
        var buf = [UInt8](count: Int(readSize), repeatedValue: 0)
        
        let numRead:ssize_t = read(socket, &buf, buf.count)
        if (numRead > 0){
            return NSData(bytes: buf, length: numRead)
        } else if (numRead == 0){
            throw SocketPosix.Error.Terminated
        } else {
            throw SocketPosix.Error.ReadError(errno)
        }
        
    }
    
    public static func recvData(socket: SocketFD, readSize: UInt = SockReadSize) throws -> (NSData, sockaddr_in) {
        
        var senderAddress:sockaddr = LegacyStructInit()
        var senderAddressLen:socklen_t = socklen_t(strideof(sockaddr))
        
        var buf = [UInt8](count: Int(readSize), repeatedValue: 0)
        let numRead = recvfrom(socket, &buf , buf.count, 0, &senderAddress, &senderAddressLen)
        if (numRead > 0){
            return (NSData(bytes: buf, length: numRead), unsafeBitCast(senderAddress, sockaddr_in.self))
        } else if (numRead == 0){
            throw SocketPosix.Error.Terminated
        } else {
            throw SocketPosix.Error.ReadError(errno)
        }
    }
    
    
    static func sendData(sendSocket: SocketFD, toAddress address: sockaddr_in, data: NSData) throws {
        
        var sent = 0
        let unsafePointer = UnsafePointer<UInt8>(data.bytes)
        
        var sAddress:sockaddr = unsafeBitCast(address, sockaddr.self)
        while (sent < data.length) {
            let sendSize = sendto(sendSocket, unsafePointer + sent, data.length - sent, 0, &sAddress , socklen_t(strideof(sockaddr)))
            
            if (sendSize <= 0) {
                close(sendSocket)
                throw SocketPosix.Error.SendError(errno)
            }
            
            sent += sendSize
        }
    }
    
    static func writeData(writeSocket: SocketFD, data: NSData) throws {
        
        var sent = 0
        let unsafePointer = UnsafePointer<UInt8>(data.bytes)
        
        while (sent < data.length) {
            let sendSize = send(writeSocket, unsafePointer + sent, data.length - sent, 0)
            
            if (sendSize <= 0){
                close(writeSocket)
                throw SocketPosix.Error.SendError(errno)
            }

            sent += sendSize
        }
    }
    
    

    
    //MARK: public: Socket Options
    // enable address reuse to sort out address binding conflicts
    static func optionEnableAddressReuse(socket: SocketFD) throws {
        var addressReuseFlag: Int32 = 1
        if (setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &addressReuseFlag, socklen_t(sizeof(Int32))) < 0){
            throw SocketPosix.Error.SetSockoptError(errno)
        }
    }
    
    static func optionDisableSigpipe(socket: SocketFD) throws {
        var noSigpipeFlag: Int32 = 1
        if (setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipeFlag, socklen_t(sizeof(Int32))) < 0){
            throw SocketPosix.Error.SetSockoptError(errno)
        }
    }
    
    static func optionSetPacketTTL(socket: SocketFD, ttl: socklen_t) throws {
        var in_ttl: socklen_t = ttl
        if (setsockopt(socket, IPPROTO_IP, IP_TTL, &in_ttl, socklen_t(strideof(socklen_t))) < 0){
            throw SocketPosix.Error.SetSockoptError(errno)
        }
    }
    
    static func optionJoinMulticastGroup(socket: SocketFD, multicastAddress: in_addr_t) throws {
        var mpreg:ip_mreq = ip_mreq(imr_multiaddr: in_addr(s_addr: multicastAddress), imr_interface: in_addr(s_addr: htonl(INADDR_ANY)))
        if (setsockopt(socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mpreg, socklen_t(strideof(ip_mreq))) < 0){
            throw SocketPosix.Error.SetSockoptError(errno)
        }
    }
    
    static func optionLeaveMulticastGroup(socket: SocketFD, multicastAddress: in_addr_t) throws {
        var mpreg:ip_mreq = ip_mreq(imr_multiaddr: in_addr(s_addr: multicastAddress), imr_interface: in_addr(s_addr: htonl(INADDR_ANY)))
        if (setsockopt(socket, IPPROTO_IP, IP_DROP_MEMBERSHIP, &mpreg, socklen_t(strideof(ip_mreq))) < 0){
            throw SocketPosix.Error.SetSockoptError(errno)
        }
    }
    
    static func optionDisableMulticastLoopback(socket: SocketFD) throws {
        var loopbackFlag: Int32 = 0
        if (setsockopt(socket, IPPROTO_IP, IP_MULTICAST_LOOP, &loopbackFlag, socklen_t(sizeof(Int32))) < 0){
            throw SocketPosix.Error.SetSockoptError(errno)
        }
    }
    
    //MARK: public: Utilities
    static func LegacyStructInit<StructType>() -> StructType {
        let structPointer = UnsafeMutablePointer<StructType>(calloc(1, sizeof(StructType)))
        
        //transferring memory ownership?
        let structMemory = structPointer.move()
        structPointer.dealloc(1)
        
        return structMemory
    }
    
    static func firstAvailableInterfaceAddress() throws -> sockaddr_in {
        
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs> = nil
        if getifaddrs(&ifaddr) == 0 {
            
            // For each interface ...
            for (var ptr = ifaddr; ptr != nil; ptr = ptr.memory.ifa_next) {
                let flags = Int32(ptr.memory.ifa_flags)
                let addr:sockaddr = ptr.memory.ifa_addr.memory
                
                // Check for running IPv4, IPv6 interfaces. Skip the loopback interface.
                if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                    if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                        
                        let addressCasted:sockaddr_in = unsafeBitCast(addr, sockaddr_in.self)
                        if (addressCasted.sin_addr.s_addr != INADDR_ANY){
                            return addressCasted
                        }
                    }
                }
            }
            
            freeifaddrs(ifaddr)
        }
        
        throw Error.CannotProvideValidAvailableInterfaceAddress
    }
    
    public static func addressString(address: sockaddr_in) -> String {
        
        var addr = address
        
        var addressStringBytes = [Int8](count: Int(INET_ADDRSTRLEN), repeatedValue: 0)
        inet_ntop(AF_INET, &(addr.sin_addr), &addressStringBytes, socklen_t(INET_ADDRSTRLEN))
        
        var vCount = 0
        for index in 0..<(addressStringBytes.count){
            if(addressStringBytes[index] != 0){
                vCount = vCount + 1
            } else {
                break;
            }
        }
        
        return NSString(bytes: addressStringBytes, length: vCount, encoding: NSASCIIStringEncoding)! as String
    }
}

//MARK: Helpers
func htons(hostshort: __uint16_t) -> __uint16_t {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt16(hostshort) : hostshort
}

func htonl(hostlong: __uint32_t) -> __uint32_t {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt32(hostlong) : hostlong
}

extension sockaddr_in: Hashable {
    
    public var hashValue: Int {
        return "\(self.sin_family),\(self.sin_port),\(self.sin_addr.s_addr)".hashValue
    }
}

public func ==(lhs: sockaddr_in, rhs: sockaddr_in) -> Bool {
    return (lhs.sin_family == rhs.sin_family &&
            lhs.sin_port == rhs.sin_port &&
            lhs.sin_addr.s_addr == rhs.sin_addr.s_addr)
}