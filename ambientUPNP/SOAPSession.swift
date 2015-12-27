//
//  SOAPSession.swift
//  AmbientUPNP
//
//  Created by Taras Vozniuk on 6/3/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

private let httpMethodPost = "POST"


class SOAPSession:NSObject, NSURLSessionDelegate {
    
    private(set) var httpSession:NSURLSession = NSURLSession()
    private(set) var httpRequest:NSURLRequest = NSURLRequest()
    
    enum Error: ErrorType {
        case DataTaskError(NSError)
        case DataTaskNoResponse
        case DataTaskReturnedWithErrorStatus(statusCode: Int)
        case DataTaskNoDataResponse
    }
    
    init(soapRequest: SOAPRequest){
        
        super.init()
        
        let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        
        let httpMutableRequest = NSMutableURLRequest(URL: soapRequest.controlURL, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 10)
        
        for key in soapRequest.headers.keys {
            httpMutableRequest.addValue(soapRequest.headers[key]!, forHTTPHeaderField: key.rawValue)
        }
        
        httpMutableRequest.HTTPMethod = httpMethodPost
        
        if let xmlBody = soapRequest.xmlBodyº {
            httpMutableRequest.HTTPBody = xmlBody.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
        } else {
            NSLog("\(self.dynamicType): \(__FUNCTION__): WARN: SOAPRequest is initialized with empty body. (soapBody is not set)")
        }
        
        self.httpRequest = httpMutableRequest
        self.httpSession = session
    }
    
    class func asynchronousRequest(request: SOAPRequest, completionHandler: (SOAPResponse?, ErrorType?) -> ()) {
        
        let session = SOAPSession(soapRequest: request)
        
        let postDataTask:NSURLSessionDataTask = session.httpSession.dataTaskWithRequest(session.httpRequest){ (dataº:NSData?, responseº:NSURLResponse?, errorº:NSError?) in
            
            var soapResponseº:SOAPResponse?
            var returnErrorº:ErrorType?
            
            defer {
                completionHandler(soapResponseº, returnErrorº)
            }
            
            if let error = errorº {
                returnErrorº = Error.DataTaskError(error)
            }
            
            guard let response = responseº as? NSHTTPURLResponse else {
                returnErrorº = Error.DataTaskNoDataResponse
                return
            }
            
            if (response.statusCode != 200){
                returnErrorº = Error.DataTaskReturnedWithErrorStatus(statusCode: response.statusCode)
            }
            
            guard let data = dataº else {
                returnErrorº = Error.DataTaskNoDataResponse
                return
            }
            
            soapResponseº = SOAPResponse(httpResponse: response, bodyData: data)
        }
        
        postDataTask.resume()
    }
    
    
    
    
    
    
}