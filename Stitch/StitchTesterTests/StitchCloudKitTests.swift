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

   var operationQueue = OperationQueue()

   override func setUp() {
      guard let selector = invocation?.selector else {
         XCTFail("No invocation")
         return
      }
      zoneString = "CloudKitTestsZone\(NSStringFromSelector(selector))"

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
            self.operationQueue.addOperation(subOperation)
         case .failure(let error):
            XCTFail("Error seting up zone \(error)")
            expectation.fulfill()
         }
      }
      operationQueue.addOperation(setupOperation)
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
                              on: operationQueue)
      { (result) in
         switch result {
         case .success(_):
            break
         case .failure(let error):
            XCTFail("There was an error deleting the database \(error)")
         }

         expectation.fulfill()
      }

      wait(for: [expectation], timeout: 10.0)
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
      setupStore()

      checkZones(exists: true)
   }

   func testTearDown() {
      tearDownStore()

      checkZones(exists: false)
   }

   func pushRecord() -> CKRecord {
      let expectation = XCTestExpectation(description: "Zone push")
      let zone = CKRecordZone.ID(zoneName: zoneString!,
                                 ownerName: CKCurrentUserDefaultName)
      let record = CKRecord(recordType: "Entry",
                            recordID: CKRecord.ID(recordName: UUID().uuidString,
                                                  zoneID: zone))
      record.setValue("be gay do crimes fk cops", forKey: "text")
      let operation = SyncPushOperation(insertedOrUpdated: [record],
                                        deletedIDs: [],
                                        database: CKContainer.default().privateCloudDatabase)
      { (result) in
         switch result {
         case .success(_):
         break //we succeeded
         case .failure(let error):
            XCTFail("Error pushing records \(error)")
         }

         expectation.fulfill()
      }
      operationQueue.addOperation(operation)
      wait(for: [expectation], timeout: 10.0)
      return record
   }

   func testPushObjects() {
      _ = pushRecord()
   }

   //This test seems to be unreliable, succeeding sometimes and failing others
   //Possibly timing issue on iCloud having enough time to make them available
   func testPullObjects() {
      let record = pushRecord()

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
      let record = pushRecord()

      let expectation = XCTestExpectation(description: "Test pull changes")
      let pullOperation = FetchChangesOperation(changesFor: CKRecordZone.ID(zoneName: zoneString!,
                                                                            ownerName: CKCurrentUserDefaultName),
                                                in: CKContainer.default().privateCloudDatabase,
                                                previousToken: nil,
                                                keysToSync: nil)
      { (result) in
         switch result {
         case .success(let syncResults):
            XCTAssertEqual(syncResults.changedInserted.count, 1)
            XCTAssertEqual(syncResults.changedInserted.first?.recordID, record.recordID)
            let text = syncResults.changedInserted.first?.value(forKey: "text") as? String
            XCTAssertNotNil(text)
            XCTAssertEqual(text, record.value(forKey: "text") as? String)
         case .failure(let error):
            XCTFail("Error pushing records \(error)")
         }

         expectation.fulfill()
      }

      operationQueue.addOperation(pullOperation)
      wait(for: [expectation], timeout: 10.0)
   }
}
