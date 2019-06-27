//
//  StitchSyncSystemTests.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/26/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
import CloudKit
import CoreData
@testable import Stitch

class StitchSyncSystemTests: XCTestCase, StitchConnectionStatus {
   var model: NSManagedObjectModel = NSManagedObjectModel.StitchTestsModel
   var coordinator: NSPersistentStoreCoordinator? = nil
   var context: NSManagedObjectContext? = nil
   var store: StitchStore? = nil
   var zoneString: String? = nil

   var internetConnectionAvailable: Bool = true

   var operationQueue = OperationQueue()

   static let doesntNeedSetupBefore: [Selector] = [
      #selector(testSyncDown)
   ]

   static let doesntNeedTearDownAfter: [Selector] = [
   ]

   override func setUp() {
      guard let selector = invocation?.selector else {
         XCTFail("No invocation")
         return
      }
      zoneString = "StitchSyncTestsZone\(NSStringFromSelector(selector))"

      if StitchSyncSystemTests.doesntNeedSetupBefore.contains(selector) {
         return
      }

      addStore()
   }

   func addStore() {
      do {
         coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         let options: [String: Any] =  [
            StitchStore.Options.ConnectionStatusDelegate: self,
            StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true),
            StitchStore.Options.ZoneNameOption: zoneString!,
            StitchStore.Options.SubscriptionNameOption: zoneString!
         ]

         var storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
         storeURL.appendPathComponent("\(zoneString!).test")
         store = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: "Success",
                                                     at: storeURL,
                                                     options: options) as? StitchStore
         XCTAssertNotNil(store)
         context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
         context?.persistentStoreCoordinator = coordinator

         NotificationCenter.default.addObserver(self,
                                                selector: #selector(syncNotification(_:)),
                                                name: StitchStore.Notifications.DidFinishSync,
                                                object: store)
         NotificationCenter.default.addObserver(self,
                                                selector: #selector(syncNotification(_:)),
                                                name: StitchStore.Notifications.DidFailSync,
                                                object: store)
         NotificationCenter.default.addObserver(self,
                                                selector: #selector(syncNotification(_:)),
                                                name: StitchStore.Notifications.DidStartSync,
                                                object: store)
      } catch {
         XCTFail("There was an error adding the persistent store \(error)")
      }
   }

   override func tearDown() {
      if StitchSyncSystemTests.doesntNeedTearDownAfter.contains(invocation!.selector) {
         return
      }

      context = nil
      let url = store?.url
      if let store = store {
         try? coordinator?.remove(store)
         self.store = nil
      }
      if let url = url {
         do {
            try FileManager.default.removeItem(at: url)
         } catch {
            XCTFail("Unable to remove store file \(error)")
         }
      }
      coordinator = nil

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

   var syncExpectation: XCTestExpectation? = nil
   func syncNotification(_ note: Notification) {
      if note.name == StitchStore.Notifications.DidFinishSync {
         syncExpectation?.fulfill()
      } else if note.name == StitchStore.Notifications.DidFailSync {
         XCTFail("Failed sync! \(String(describing: note.userInfo))")
         syncExpectation?.fulfill()
      } else if note.name == StitchStore.Notifications.DidStartSync {
         print("started")
      } else {
         XCTFail("Unexpected sync note")
      }
   }

   func testStoreReady() {
      syncExpectation = XCTestExpectation(description: "Sync Happened")
      store?.triggerSync(.storeAdded)

      guard let expectation = syncExpectation else { return }
      wait(for: [expectation], timeout: 10.0)
   }

   func addEntryAndSave() -> Entry? {
      guard let context = context else {
         XCTFail("Context should not be nil")
         return nil
      }

      let entry = Entry(entity: Entry.entity(), insertInto: context)
      entry.text = "be gay do crimes fk cops"

      save()
      return entry
   }
   func save() {
      do {
         try context?.save()
      } catch {
         XCTFail("Database should save ok \(error)")
      }
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

   func testPushChanges() {
      guard let entry = addEntryAndSave() else {
         XCTFail("Failed to add entry")
         return
      }
      syncExpectation = XCTestExpectation(description: "Sync Happened")

      if let expectation = syncExpectation {
         wait(for: [expectation], timeout: 10.0)
      }

      let record = try? store?.ckRecordForOutwardObject(entry)
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
            XCTAssertEqual(syncResults.changedInserted.first?.recordID, record?.recordID)
            let text = syncResults.changedInserted.first?.value(forKey: "text") as? String
            XCTAssertNotNil(text)
            XCTAssertEqual(text, entry.text)
         case .failure(let error):
            XCTFail("Error pushing records \(error)")
         }

         expectation.fulfill()
      }

      operationQueue.addOperation(pullOperation)
      wait(for: [expectation], timeout: 10.0)
   }

   func testSyncDown() {
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

      let record = pushRecord()

      sleep(5)

      addStore()
      store?.triggerSync(.storeAdded)

      syncExpectation = XCTestExpectation(description: "Sync Happened")

      if let expectation = syncExpectation {
         wait(for: [expectation], timeout: 10.0)
      }

      let fetch = Entry.fetchRequest() as NSFetchRequest<Entry>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1)
      guard let object = results?.first else {
         XCTFail("No objects")
         return
      }
      let syncedRecord = try? store?.ckRecordForOutwardObject(object)
      XCTAssertNotNil(syncedRecord)
      XCTAssertEqual(syncedRecord?.recordID, record.recordID)
   }
}
