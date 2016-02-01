//
//  PosixInternals.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 3/28/15.
//  reviewed on 9/3/15 by ambientlight.
//
//  Copyright (c) 2015 ambientlight. All rights reserved.
//


import Foundation


let WLAN = "en0"

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
public struct PosixInternals
{
    public enum Error:ErrorType {
        case SocketInitFailed(Int32)
        case CannotBindSocket(Int32)
        case ListenError(Int32)
        
        case Terminated
        
        case ReadError(Int32)
        case SendError(Int32)
        case SetSockoptError(Int32)
        case IOCTLFailed(Int32)
        
        case CannotProvideValidAvailableInterfaceAddress
        case StringIsNotAnASCIIString
    }
    
    //MARK: public: Methods
    
    public static func initMulticastUDPSocket(port: in_port_t, multicastAddress: sockaddr_in) throws -> SocketFD {
        
        
        
        let multicastSocket:SocketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (multicastSocket < 0) {
            throw PosixInternals.Error.SocketInitFailed(errno)
        }
        
        let address:sockaddr_in = multicastAddress
        try optionEnableAddressReuse(multicastSocket)
        try optionDisableSigpipe(multicastSocket)
        try optionJoinMulticastGroup(multicastSocket, multicastAddress: address.sin_addr.s_addr)
        
        var sAddress:sockaddr = unsafeBitCast(address, sockaddr.self)
        if (bind(multicastSocket, &sAddress, socklen_t(strideof(sockaddr_in))) < 0){
            release(multicastSocket)
            throw PosixInternals.Error.CannotBindSocket(errno)
        }
        
        return multicastSocket
    }
    
    public static func initPlainUPDSocket() throws -> SocketFD {
        
        let incomeSocket:SocketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (incomeSocket < 0) {
            throw PosixInternals.Error.SocketInitFailed(errno)
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
            throw PosixInternals.Error.SocketInitFailed(errno)
        }
        
        try optionEnableAddressReuse(streamSocket)
        try optionDisableSigpipe(streamSocket)
        try optionSetPacketTTL(streamSocket, ttl: 2)
        
        var addressToBind = address
        addressToBind.sin_port = htons(port)
        var sAddress:sockaddr = unsafeBitCast(addressToBind, sockaddr.self)
        if (bind(streamSocket, &sAddress, socklen_t(strideof(sockaddr_in))) < 0){
            release(streamSocket)
            throw PosixInternals.Error.CannotBindSocket(errno)
        }
        
        if (listen(streamSocket, SOCK_LISTEN_QUEUE_MAX) < 0){
            release(streamSocket)
            throw PosixInternals.Error.ListenError(errno)
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
            throw PosixInternals.Error.Terminated
        } else {
            throw PosixInternals.Error.ReadError(errno)
        }
        
    }
    
    public static func recvData(socket: SocketFD, readSize: UInt = SockReadSize) throws -> (NSData, sockaddr_in) {
        
        var senderAddress:sockaddr = sockaddr()
        var senderAddressLen:socklen_t = socklen_t(strideof(sockaddr))
        
        var buf = [UInt8](count: Int(readSize), repeatedValue: 0)
        let numRead = recvfrom(socket, &buf , buf.count, 0, &senderAddress, &senderAddressLen)
        if (numRead > 0){
            return (NSData(bytes: buf, length: numRead), unsafeBitCast(senderAddress, sockaddr_in.self))
        } else if (numRead == 0){
            throw PosixInternals.Error.Terminated
        } else {
            throw PosixInternals.Error.ReadError(errno)
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
                throw PosixInternals.Error.SendError(errno)
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
                throw PosixInternals.Error.SendError(errno)
            }

            sent += sendSize
        }
    }
    
    //MARK: - public: Utilities
    
    public static func numBytesAvailableToRead(forSocket socket: SocketFD) throws -> Int {
        var bytesLeft:Int32 = 0
        if (_ioctl(socket, FIONREAD, &bytesLeft) < 0){
            throw PosixInternals.Error.IOCTLFailed(errno)
        } else {
            return Int(bytesLeft)
        }
    }
    
    public static func interfaceAddress(forInterfaceWithName interfaceName: String) throws -> sockaddr_in {
        
        guard let cString = interfaceName.cStringUsingEncoding(NSASCIIStringEncoding) else {
            throw Error.StringIsNotAnASCIIString
        }
        
        let addressPtr = UnsafeMutablePointer<sockaddr>.alloc(1)
        let ioctl_res = _interfaceAddressForName(strdup(cString), addressPtr)
        let address = addressPtr.move()
        addressPtr.dealloc(1)
        
        if ioctl_res < 0 {
            throw Error.IOCTLFailed(errno)
        } else {
            return unsafeBitCast(address, sockaddr_in.self)
        }
    }
    
    public static func availableInterfacesNames() -> [String] {
        
        let MAX_INTERFACES = 128;
        
        var interfaceNames = [String]()
        let interfaceNamePtr = UnsafeMutablePointer<Int8>.alloc(Int(IF_NAMESIZE))
        for interfaceIndex in 1...MAX_INTERFACES {
            if (if_indextoname(UInt32(interfaceIndex), interfaceNamePtr) != nil){
                if let interfaceName = String.fromCString(interfaceNamePtr) {
                    interfaceNames.append(interfaceName)
                }
            } else {
                break
            }
        }
        
        interfaceNamePtr.dealloc(Int(IF_NAMESIZE))
        return interfaceNames
    }
    
    public static func addressString(address: sockaddr_in) -> String {
        
        return String.fromCString(inet_ntoa(address.sin_addr))!
        
        /*
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
        */
    }
    
    //MARK: - public: Socket Options
    // enable address reuse to sort out address binding conflicts
    static func optionEnableAddressReuse(socket: SocketFD) throws {
        var addressReuseFlag: Int32 = 1
        if (setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &addressReuseFlag, socklen_t(sizeof(Int32))) < 0){
            throw PosixInternals.Error.SetSockoptError(errno)
        }
    }
    
    static func optionDisableSigpipe(socket: SocketFD) throws {
        var noSigpipeFlag: Int32 = 1
        if (setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipeFlag, socklen_t(sizeof(Int32))) < 0){
            throw PosixInternals.Error.SetSockoptError(errno)
        }
    }
    
    static func optionSetPacketTTL(socket: SocketFD, ttl: socklen_t) throws {
        var in_ttl: socklen_t = ttl
        if (setsockopt(socket, IPPROTO_IP, IP_TTL, &in_ttl, socklen_t(strideof(socklen_t))) < 0){
            throw PosixInternals.Error.SetSockoptError(errno)
        }
    }
    
    static func optionJoinMulticastGroup(socket: SocketFD, multicastAddress: in_addr_t) throws {
        var mpreg:ip_mreq = ip_mreq(imr_multiaddr: in_addr(s_addr: multicastAddress), imr_interface: in_addr(s_addr: htonl(INADDR_ANY)))
        if (setsockopt(socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mpreg, socklen_t(strideof(ip_mreq))) < 0){
            throw PosixInternals.Error.SetSockoptError(errno)
        }
    }
    
    static func optionLeaveMulticastGroup(socket: SocketFD, multicastAddress: in_addr_t) throws {
        var mpreg:ip_mreq = ip_mreq(imr_multiaddr: in_addr(s_addr: multicastAddress), imr_interface: in_addr(s_addr: htonl(INADDR_ANY)))
        if (setsockopt(socket, IPPROTO_IP, IP_DROP_MEMBERSHIP, &mpreg, socklen_t(strideof(ip_mreq))) < 0){
            throw PosixInternals.Error.SetSockoptError(errno)
        }
    }
    
    static func optionDisableMulticastLoopback(socket: SocketFD) throws {
        var loopbackFlag: Int32 = 0
        if (setsockopt(socket, IPPROTO_IP, IP_MULTICAST_LOOP, &loopbackFlag, socklen_t(sizeof(Int32))) < 0){
            throw PosixInternals.Error.SetSockoptError(errno)
        }
    }
    
}

//MARK: - sockaddr_in: Hashable
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


//MARK: - POSIX Defs
func htons(hostshort: UInt16) -> UInt16 {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt16(hostshort) : hostshort
}

func htonl(hostlong: UInt32) -> UInt32 {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt32(hostlong) : hostlong
}

func _IOC(inOut: UInt, _ group: UInt, _ num: UInt, _ len: UInt) -> UInt {
    return UInt(inOut | ((len & UInt(IOCPARM_MASK)) << 16) | ((group) << 8) | (num))
}
func _IOR<T>(g: UInt, _ n: UInt, _ t: T.Type) -> UInt {
    return _IOC(IOC_OUT, g, n, UInt(strideof(t)))
}
func _IOWR<T>(g: UInt, _ n: UInt, _ t: T.Type) -> UInt {
    return _IOC(IOC_INOUT, g, n, UInt(strideof(t)))
}

var IOC_OUT: UInt = 0x40000000
var IOC_IN: UInt = 0x80000000
var IOC_INOUT: UInt { return (IOC_OUT | IOC_IN) }

var FIONREAD: UInt { return _IOR(0x66, 127, Int32.self) }
