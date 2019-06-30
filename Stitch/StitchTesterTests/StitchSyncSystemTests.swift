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

class StitchSyncSystemTests: StitchTesterRoot {
   override var storeOptions: [String : Any] {
      return [
         StitchStore.Options.ConnectionStatusDelegate: self,
         StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true),
         StitchStore.Options.ZoneNameOption: zoneString!,
         StitchStore.Options.SubscriptionNameOption: zoneString!
      ]
   }

   override var internetConnectionAvailable: Bool { return true }

   static let doesntNeedSetupBefore: [Selector] = [
      #selector(testSyncDown),
      #selector(testSyncDownLarge)
   ]

   static let doesntNeedTearDownAfter: [Selector] = [
   ]

   override func setUp() {
      super.setUp()
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

   override func tearDown() {
      super.tearDown()
      if StitchSyncSystemTests.doesntNeedTearDownAfter.contains(invocation!.selector) {
         return
      }

      removeStore(true)
      tearDownZone()
   }

   func testStoreReady() {
      syncExpectation = XCTestExpectation(description: "Sync Happened")
      store?.triggerSync(.storeAdded)

      guard let expectation = syncExpectation else { return }
      wait(for: [expectation], timeout: 10.0)
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

      pullChanges { (syncResults) in
         XCTAssertEqual(syncResults.changedInserted.count, 1)
         XCTAssertEqual(syncResults.changedInserted.first?.recordID, record?.recordID)
         let text = syncResults.changedInserted.first?.value(forKey: "text") as? String
         XCTAssertNotNil(text)
         XCTAssertEqual(text, entry.text)
      }
   }

   func testSyncDown() {
      setupZone()

      let record = pushEntry()

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
      XCTAssertEqual(record.value(forKey: "text") as? String, object.text)
   }

   func testSyncUpLarge() {
      var entries = Set<Entry>()
      for index in 0..<1000 {
         if let entry = addEntry() {
            entry.text = "number: \(index)"
            entries.insert(entry)
         }
      }
      save()

      syncExpectation = XCTestExpectation(description: "Sync Happened")

      if let expectation = syncExpectation {
         wait(for: [expectation], timeout: 30.0)
      }

      let zone = CKRecordZone.ID(zoneName: zoneString!,
                                 ownerName: CKCurrentUserDefaultName)

      pullChanges { (syncResults) in
         var syncedEntries = Set<Entry>()
         let syncedRecordIDs = Set<CKRecord.ID>(syncResults.changedInserted.map {
            $0.recordID
         })

         for entry in entries {
            if let backingID = try? self.store?.backingObject(for: entry).ckRecordID(zone: zone),
               syncedRecordIDs.contains(backingID)
            {
               syncedEntries.insert(entry)
            }
         }
         XCTAssertEqual(syncedEntries.count, entries.count)
      }
   }

   func testSyncDownLarge() {
      setupZone()
      var recordInfos = [(type: String, info: [String: CKRecordValue])]()
      for index in 0..<1000 {
         recordInfos.append((type: "Entry", info: ["text" : "\(index)" as CKRecordValue]))
      }
      let pushedRecords = pushRecords(records: recordInfos)

      addStore()
      store?.triggerSync(.storeAdded)

      syncExpectation = XCTestExpectation(description: "Sync Happened")

      if let expectation = syncExpectation {
         wait(for: [expectation], timeout: 30.0)
      }

      let fetch = Entry.fetchRequest() as NSFetchRequest<Entry>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1000)

      let zone = CKRecordZone.ID(zoneName: zoneString!,
                                 ownerName: CKCurrentUserDefaultName)
      let pushedIDs: Set<CKRecord.ID> = Set<CKRecord.ID>(pushedRecords.map { $0.recordID })
      var backingIDs = [CKRecord.ID]()
      for result in results ?? [] {
         if let backingID = try? self.store?.backingObject(for: result).ckRecordID(zone: zone),
            pushedIDs.contains(backingID)
         {
            backingIDs.append(backingID)
         }
      }

      XCTAssertEqual(pushedRecords.count, backingIDs.count)
   }

   func testPushRelationship() {
      let entry = addEntry()
      let location = addLocation()
      entry?.location = location
      save()

      syncExpectation = XCTestExpectation(description: "Sync Happened")

      if let expectation = syncExpectation {
         wait(for: [expectation], timeout: 30.0)
      }

      pullChanges { (syncResults) in
         XCTAssertEqual(syncResults.changedInserted.count, 2)
         guard let entryRecord = syncResults.changedInserted.first(where: { $0.recordType == "Entry" }),
            let locationRecord = syncResults.changedInserted.first(where: { $0.recordType == "Location" }) else
         {
            XCTFail("Need an entry and a location record both")
            return
         }
         XCTAssert(entryRecord.value(forKey: "location") is CKRecord.Reference)
         XCTAssertEqual((entryRecord.value(forKey: "location") as? CKRecord.Reference)?.recordID, locationRecord.recordID)
      }
   }
}
