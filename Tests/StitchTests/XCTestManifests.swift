//
//  Testing.swift
//  Stitch
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(StitchTests.allTests),
        testCase(StitchStoreAddedTests.allTests),
    ]
}
#endif
