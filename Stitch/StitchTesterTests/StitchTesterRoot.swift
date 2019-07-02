//
//  StitchTesterRoot.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/27/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
import CoreData
import CloudKit
@testable import Stitch

let CloudKitID = "iCloud.com.darkchocolatesoftware.StitchTester"

class StitchTesterRoot: XCTestCase, StitchConnectionStatus {
   var model: NSManagedObjectModel = NSManagedObjectModel.StitchTestsModel
   var coordinator: NSPersistentStoreCoordinator? = nil
   var context: NSManagedObjectContext? = nil
   var store: StitchStore? = nil
   var zoneString: String? = nil

   var internetConnectionAvailable: Bool = false
   var operationQueue = OperationQueue()

   var storeOptions: [String: Any] {
      return [
         StitchStore.Options.BackingStoreType: NSInMemoryStoreType,
         StitchStore.Options.ConnectionStatusDelegate: self,
         StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true),
         StitchStore.Options.CloudKitContainerIdentifier: CloudKitID
      ]
   }

   override func setUp() {
      super.setUp()
      guard let selector = invocation?.selector else {
         XCTFail("No invocation")
         return
      }
      zoneString = "CloudKitTestsZone\(NSStringFromSelector(selector))"
   }

   func addStore(_ modelURL: URL? = nil) {
      do {
         if let modelURL = modelURL,
            let model = NSManagedObjectModel(contentsOf: modelURL)
         {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         } else {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         }

         var storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
         storeURL.appendPathComponent("\(zoneString!).test")
         store = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: "Success",
                                                     at: storeURL,
                                                     options: storeOptions) as? StitchStore
         XCTAssertNotNil(store)
         context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
         context?.persistentStoreCoordinator = coordinator
      } catch {
         XCTFail("There was an error adding the persistent store \(error)")
      }
   }

   func removeStore(_ fromDisk: Bool = false) {
      context = nil
      let url = store?.url
      if let store = store {
         try? coordinator?.remove(store)
         self.store = nil
      }
      coordinator = nil
      
      if fromDisk, let url = url {
         do {
            try FileManager.default.removeItem(at: url)
         } catch {
            XCTFail("Unable to remove store file \(error)")
         }
      }
   }

   override func tearDown() {
      // Put teardown code here. This method is called after the invocation of each test method in the class.
      NotificationCenter.default.removeObserver(self, name: nil, object: nil)
      super.tearDown()
   }

   func awaitSync() {
      let syncExpectation = XCTNSNotificationExpectation(name: StitchStore.Notifications.DidFinishSync,
                                                         object: store)
      syncExpectation.expectationDescription = "Waiting for sync"
      wait(for: [syncExpectation], timeout: 30.0)
   }

   func addEntry() -> Entry? {
      guard let context = context else {
         XCTFail("Context should not be nil")
         return nil
      }

      let entry = Entry(entity: Entry.entity(), insertInto: context)
      entry.text = "be gay do crimes fk cops"
      return entry
   }
   func addEntryAndSave() -> Entry? {
      let entry = addEntry()
      save()
      return entry
   }
   func addLocation() -> Location? {
      guard let context = context else {
         XCTFail("Context should not be nil")
         return nil
      }

      let location = Location(entity: Location.entity(), insertInto: context)
      location.displayName = "Home"
      return location
   }
   func addLocationAndSave() -> Location? {
      let location = addLocation()
      save()
      return location
   }
   func save() {
      do {
         try context?.save()
      } catch {
         XCTFail("Database should save ok \(error)")
      }
   }

   func setupZone() {
      let expectation = XCTestExpectation(description: "Store setup")

      let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: zoneString!,
                                                      ownerName: CKCurrentUserDefaultName))
      let database = CKContainer(identifier: CloudKitID).privateCloudDatabase

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

   func tearDownZone() {
      let expectation = XCTestExpectation(description: "Store teardown")

      let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: zoneString!,
                                                      ownerName: CKCurrentUserDefaultName))
      let database = CKContainer(identifier: CloudKitID).privateCloudDatabase
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

   struct RecordInfo {
      let type: String
      let info: [String: CKRecordValue]
      var recordID: CKRecord.ID? = nil
   }
   func pushRecords(records: [RecordInfo] = [],
                    deletedIDs: [CKRecord.ID] = []) -> [CKRecord]
   {
      let expectation = XCTestExpectation(description: "Zone push")
      let zone = CKRecordZone.ID(zoneName: zoneString!,
                                 ownerName: CKCurrentUserDefaultName)
      let records: [CKRecord] = records.map {
         let record = CKRecord(recordType: $0.type,
                               recordID: $0.recordID ?? CKRecord.ID(recordName: UUID().uuidString,
                                                                    zoneID: zone))
         record.setValuesForKeys($0.info)
         return record
      }
      let operation = SyncPushOperation(insertedOrUpdated: records,
                                        deletedIDs: deletedIDs,
                                        database: CKContainer(identifier: CloudKitID).privateCloudDatabase)
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
      wait(for: [expectation], timeout: 30.0)
      return records
   }

   func pushRecord(_ type: String, info: [String: CKRecordValue]) -> CKRecord {
      return pushRecords(records: [RecordInfo(type: type,
                                              info: info)]).first!
   }

   func pushEntry() -> CKRecord {
      return pushRecord("Entry", info: ["text": "be gay do crimes fk cops" as CKRecordValue])
   }

   func pullChanges(_ handler: @escaping (FetchedChanges) -> Void) {
      let expectation = XCTestExpectation(description: "Test pull changes")
      let pullOperation = FetchChangesOperation(changesFor: CKRecordZone.ID(zoneName: zoneString!,
                                                                            ownerName: CKCurrentUserDefaultName),
                                                in: CKContainer(identifier: CloudKitID).privateCloudDatabase,
                                                previousToken: nil,
                                                keysToSync: nil)
      { (result) in
         switch result {
         case .success(let syncResults):
            handler(syncResults)
         case .failure(let error):
            XCTFail("Error pushing records \(error)")
         }
         expectation.fulfill()
      }

      operationQueue.addOperation(pullOperation)
      wait(for: [expectation], timeout: 10.0)
   }
}
