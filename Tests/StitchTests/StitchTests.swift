//
//  StitchTests.swift
//  Stitch
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import XCTest
import CoreData
@testable import Stitch

final class StitchTests: XCTestCase {
   func testStoreType() {
      XCTAssertEqual(StitchStore.storeType, NSStringFromClass(StitchStore.self), "StitchStore's type should be StitchStore")
      XCTAssertNotNil(NSPersistentStoreCoordinator.registeredStoreTypes[StitchStore.storeType], "StitchStore not registered")
   }

   static var allTests = [
      ("testStoreType", testStoreType),
   ]
}
