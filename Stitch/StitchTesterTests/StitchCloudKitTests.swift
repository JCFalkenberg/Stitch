//
//  StitchCloudKitTests.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/25/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
import CloudKit
import CoreData
@testable import Stitch

class StitchCloudKitTests: XCTestCase {
   var zoneString: String? = nil

   override func setUp() {
      guard let selector = invocation?.selector else {
         XCTFail("No invocation")
         return
      }
      zoneString = "CloudKitTestsZone-\(NSStringFromSelector(selector))"
      print("\(zoneString!)")

      if selector == #selector(testSetup) {
         // The rest of this will be done in the testSetup() itself
         return
      }

      setupStore()
   }

   func setupStore() {
      let expectation = XCTestExpectation(description: "Store setup")

      let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: zoneString!,
                                                      ownerName: CKCurrentUserDefaultName))
      let database = CKContainer.default().privateCloudDatabase

      let setupOperation = CKModifyRecordZonesOperation(create: zone,
                                                        in: database)
      { (result) in
         switch result {
         case .success(_):
            let subOperation = CKModifySubscriptionsOperation(create: zone.zoneID,
                                                              name: self.zoneString!,
                                                              in: database)
            { (result) in
               switch result {
               case .success(_):
                  print("We succeeded")
                  break
               case .failure(let error):
                  XCTFail("There was an error deleting the database \(error)")
               }

               expectation.fulfill()
            }
            OperationQueue.main.addOperation(subOperation)
         case .failure(let error):
            XCTFail("Error seting up zone \(error)")
            expectation.fulfill()
         }
      }
      OperationQueue.main.addOperation(setupOperation)
      wait(for: [expectation], timeout: 10.0)
   }

   override func tearDown() {
      if invocation?.selector == #selector(testTearDown) {
         // The rest of this will be done in the testSetup() itself
         return
      }

      tearDownStore()
   }

   func tearDownStore() {
      let expectation = XCTestExpectation(description: "Store teardown")

      let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: zoneString!,
                                                      ownerName: CKCurrentUserDefaultName))
      let database = CKContainer.default().privateCloudDatabase
      StitchStore.destroyZone(zone: zone,
                              in: database,
                              on: OperationQueue.main)
      { (result) in
         switch result {
         case .success(_):
            print("We succeeded")
            break
         case .failure(let error):
            XCTFail("There was an error deleting the database \(error)")
         }

         expectation.fulfill()
      }

      wait(for: [expectation], timeout: 10.0)
   }

   func testSetup() {
      setupStore()
   }

   func testTearDown() {
      tearDownStore()
   }

   func testPushObjects() {
   }

   func testPullObjects() {
   }
}
