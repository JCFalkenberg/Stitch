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
            break
         case .failure(let error):
            XCTFail("There was an error deleting the database \(error)")
         }

         expectation.fulfill()
      }

      wait(for: [expectation], timeout: 30.0)
   }

   func checkZones(exists: Bool) {
      let zoneExpectation = XCTestExpectation(description: "Zone fetch")
      let recordZoneID = CKRecordZone.ID(zoneName: zoneString!)
      let fetchZonesOp = CKFetchRecordZonesOperation(recordZoneIDs: [recordZoneID])
      fetchZonesOp.fetchRecordZonesCompletionBlock = { (zoneDict, error) in
         if let error = error as! CKError? {
            if exists {
               XCTFail("there was an error retrieving zones \(error)")
            } else {
               XCTAssertEqual(error.code, CKError.partialFailure)
               let partialError = error.partialErrorsByItemID?[recordZoneID] as! CKError
               XCTAssertNotNil(partialError)
               XCTAssertEqual(partialError.code, CKError.zoneNotFound)
            }
         } else {
            if exists {
               XCTAssertEqual(zoneDict?.count, 1)
            } else {
               XCTAssertNotEqual(zoneDict?.count, 1)
            }
         }

         zoneExpectation.fulfill()
      }
      OperationQueue.main.addOperation(fetchZonesOp)
      wait(for: [zoneExpectation], timeout: 30.0)

      let subscriptionExpectation = XCTestExpectation(description: "Subscription fetch")
      let subscriptionID = CKSubscription.ID(zoneString!)
      let fetchSubscriptionOp = CKFetchSubscriptionsOperation(subscriptionIDs: [subscriptionID])
      fetchSubscriptionOp.fetchSubscriptionCompletionBlock = { (subscriptionDict, error) in
         if let error = error as! CKError? {
            if exists {
               XCTFail("there was an error retrieving subscriptions \(error)")
            } else {
               XCTAssertEqual(error.code, CKError.partialFailure)
               let partialError = error.partialErrorsByItemID?[subscriptionID] as! CKError
               XCTAssertNotNil(partialError)
               XCTAssertEqual(partialError.code, CKError.unknownItem)
            }
         } else {
            if exists {
               XCTAssertEqual(subscriptionDict?.count, 1)
            } else {
               XCTAssertNotEqual(subscriptionDict?.count, 1)
            }
         }

         subscriptionExpectation.fulfill()
      }
      OperationQueue.main.addOperation(fetchSubscriptionOp)
      wait(for: [subscriptionExpectation], timeout: 30.0)
   }

   func testSetup() {
      setupStore()

      checkZones(exists: true)
   }

   func testTearDown() {
      tearDownStore()

      checkZones(exists: false)
   }

   func testPushObjects() {
   }

   func testPullObjects() {
   }
}
