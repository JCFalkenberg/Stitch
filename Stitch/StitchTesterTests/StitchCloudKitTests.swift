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

class StitchCloudKitTests: StitchTesterRoot {
   override func setUp() {
      super.setUp()
      internetConnectionAvailable = true
      if invocation?.selector == #selector(testSetup) {
         // The rest of this will be done in the testSetup() itself
         return
      }

      setupZone()
   }

   override func tearDown() {
      super.tearDown()
      if invocation?.selector == #selector(testTearDown) {
         // The rest of this will be done in the testSetup() itself
         return
      }

      tearDownZone()
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
      operationQueue.addOperation(fetchZonesOp)
      wait(for: [zoneExpectation], timeout: 10.0)

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
      operationQueue.addOperation(fetchSubscriptionOp)
      wait(for: [subscriptionExpectation], timeout: 10.0)
   }

   func testSetup() {
      setupZone()

      checkZones(exists: true)
   }

   func testTearDown() {
      tearDownZone()

      checkZones(exists: false)
   }

   func testPushObjects() {
      _ = pushEntry()
   }

   //This test seems to be unreliable, succeeding sometimes and failing others
   //Possibly timing issue on iCloud having enough time to make them available
   func testPullObjects() {
      let record = pushEntry()

      sleep(5) //Sleep for a bit to let it process

      let expectation = XCTestExpectation(description: "Entry pull")
      let zone = CKRecordZone.ID(zoneName: zoneString!,
                                 ownerName: CKCurrentUserDefaultName)
      let pullOperation = EntityDownloadOperationWrapper(entityName: "Entry",
                                                         keysToSync: nil,
                                                         database: CKContainer.default().privateCloudDatabase,
                                                         zone: zone)
      { (records, error) in
         if let error = error {
            XCTFail("Error pulling records \(error)")
         } else if let records = records {
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?.recordID, record.recordID)
            let text = records.first?.value(forKey: "text") as? String
            XCTAssertNotNil(text)
            XCTAssertEqual(text, record.value(forKey: "text") as? String)
         } else {
            XCTFail("No error or records...")
         }

         expectation.fulfill()
      }

      operationQueue.addOperation(pullOperation)
      wait(for: [expectation], timeout: 10.0)
   }

   func testPullChanges() {
      let record = pushEntry()

      pullChanges { (syncResults) in
         XCTAssertEqual(syncResults.changedInserted.count, 1)
         XCTAssertEqual(syncResults.changedInserted.first?.recordID, record.recordID)
         let text = syncResults.changedInserted.first?.value(forKey: "text") as? String
         XCTAssertNotNil(text)
         XCTAssertEqual(text, record.value(forKey: "text") as? String)
      }
   }
}
