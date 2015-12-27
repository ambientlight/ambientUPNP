//
//  NSRegularExpression.swift
//  ambientUPNP
//
//  Created by Taras Vozniuk on 4/6/15.
//  Copyright (c) 2015 ambientlight. All rights reserved.
//

import Foundation

public extension NSRegularExpression {
    
    public class func capturingGroupsOfStringFirstMatch(pstring: String, pattern: String) throws -> [String]? {
        
        let regex = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
        if let match = regex.firstMatchInString(pstring, options: [], range: NSMakeRange(0, pstring.utf16.count)){
            
            if (regex.numberOfCaptureGroups == 0) {
                return nil
            }
            
            var groupStrings:[String] = [String]()
            for index in 1...regex.numberOfCaptureGroups {
                let groupRange:NSRange = match.rangeAtIndex(index)
                groupStrings.append((pstring as NSString).substringWithRange(groupRange))
            }
            
            return groupStrings
        }
        
        return nil
    }
    
    public class func capturingGroupsOfStringForEachMatch(pstring: String, pattern: String, resultClosure: ([String]) -> ()) throws {
        
        let regex = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
        
        let matches = regex.matchesInString(pstring, options: [], range: NSMakeRange(0, pstring.utf16.count))
        for match: NSTextCheckingResult in matches as [NSTextCheckingResult] {
            
            if (regex.numberOfCaptureGroups == 0) {
                continue
            }
            
            var groupStrings:[String] = [String]()
            for index in 1...regex.numberOfCaptureGroups {
                let groupRange:NSRange = match.rangeAtIndex(index)
                groupStrings.append((pstring as NSString).substringWithRange(groupRange))
            }
            
            resultClosure(groupStrings)
        }
    }
    
    public class func stringBeforeAndIncludingFirstMatchOfString(pstring: String, pattern: String) throws -> String? {
        
        let regex = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
        
        if let match = regex.firstMatchInString(pstring, options: [], range: NSMakeRange(0, pstring.utf16.count)){
            
            
            let matchRange = match.rangeAtIndex(0)
            let stringBeforeRange = NSMakeRange(0, matchRange.location + matchRange.length)
            
            return ((pstring as NSString).substringWithRange(stringBeforeRange))
        }
        
        return nil
    }
    
    public class func stringAfterFirstMatchOfString(pstring: String, pattern: String) throws -> String? {
        
        let regex = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
        
        if let match = regex.firstMatchInString(pstring, options: [], range: NSMakeRange(0, pstring.utf16.count)){
            
            let matchRange = match.rangeAtIndex(0)
            let stringAfterRange = NSMakeRange(matchRange.location + matchRange.length, pstring.utf16.count - (matchRange.location + matchRange.length))
            
            return ((pstring as NSString).substringWithRange(stringAfterRange))
        }
        
        return nil
    }
    
    public class func numberOfMatchesInString(pstring: String, pattern: String) throws -> UInt {
        
        let regex = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
        let matches = regex.matchesInString(pstring, options: [], range: NSMakeRange(0, pstring.utf16.count))
        return UInt(matches.count)
    }
}
