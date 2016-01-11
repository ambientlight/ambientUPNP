//
//  ambientUPNPTests.swift
//  ambientUPNPTests
//
//  Created by Taras Vozniuk on 9/2/15.
//  Copyright © 2015 ambientlight. All rights reserved.
//

import XCTest
@testable import ambientUPNP

class ambientUPNPTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssert(true, "Pass")
                
        let controlPoint = UPNPControlPoint()
        do {
            try controlPoint.start()
            
            controlPoint.stop { (didSucceed: Bool) in
                
                if didSucceed {
                    try! controlPoint.start()
                    controlPoint.stop { (didSucceed: Bool) in
                        
                        if didSucceed {
                            try! controlPoint.start()
                            controlPoint.stop { (didSuceed: Bool) in
                                
                                if didSuceed {
                                    try! controlPoint.start()
                                }
                            }
                        }
                    }
                }
                
            }
            
            
            sleep(3600)
        } catch {
            print(error)
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
