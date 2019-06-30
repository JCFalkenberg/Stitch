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
         StitchStore.Options.SubscriptionNameOption: zoneString!,
         StitchStore.Options.ExcludedUnchangingAsyncAssetKeys: ["externalData"]
      ]
   }

   override var internetConnectionAvailable: Bool { return true }

   static let doesntNeedSetupBefore: [Selector] = [
      #selector(testSyncDown),
      #selector(testSyncDownLarge),
      #selector(testAsyncDataDownload)
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
      store?.triggerSync(.storeAdded)

      awaitSync()
   }

   func testPushChanges() {
      guard let entry = addEntryAndSave() else {
         XCTFail("Failed to add entry")
         return
      }
      awaitSync()

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

      awaitSync()

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

      awaitSync()

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
      var recordInfos = [RecordInfo]()
      for index in 0..<1000 {
         recordInfos.append(RecordInfo(type: "Entry",
                                       info: ["text" : "\(index)" as CKRecordValue]))
      }
      let pushedRecords = pushRecords(records: recordInfos)

      addStore()
      store?.triggerSync(.storeAdded)

      awaitSync()

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

      awaitSync()

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

   func testLocalDelete() {
      guard let entry = addEntryAndSave() else {
         XCTFail("No entry created")
         return
      }

      awaitSync()

      guard let recordID = try? store?.ckRecordForOutwardObject(entry)?.recordID else {
         XCTFail("Unable to retrieve record ID")
         return
      }
      context?.delete(entry)
      save()

      awaitSync()

      pullChanges { (syncResults) in
         XCTAssertEqual(syncResults.changedInserted.count, 0)
         XCTAssertEqual(syncResults.deletedByType.count, 1)
         XCTAssertEqual(syncResults.deletedByType["Entry"]?.count, 1)
         XCTAssertEqual(syncResults.deletedByType["Entry"]?.first, recordID)
      }
   }

   func testRemoteDelete() {
      guard let entry = addEntryAndSave() else {
         XCTFail("No entry created")
         return
      }

      awaitSync()

      guard let recordID = try? store?.ckRecordForOutwardObject(entry)?.recordID else {
         XCTFail("Unable to retrieve record ID")
         return
      }

      _ = pushRecords(deletedIDs: [recordID])

      store?.triggerSync(.push)

      awaitSync()

      let fetch = Entry.fetchRequest() as NSFetchRequest<Entry>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 0)
   }

   func testAsyncDataDownload() {
      setupZone()

      let testData = Data([0x61, 0x6e, 0x64, 0x61, 0x74, 0x61, 0x30, 0x31])

      var tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      tempURL = tempURL.appendingPathComponent("CKAssetTemp")
      try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
      tempURL = tempURL.appendingPathComponent(UUID().uuidString)
      try? testData.write(to: tempURL, options: [.atomic])
      let asset = CKAsset(fileURL: tempURL)
      
      let pushed = pushRecords(records: [RecordInfo(type: "AllTypes",
                                                    info: ["externalData": asset])])

      addStore()
      store?.triggerSync(.storeAdded)

      awaitSync()

      let fetch = AllTypes.fetchRequest() as NSFetchRequest<AllTypes>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1)
      guard let first = results?.first else {
         XCTFail("No first result? weird")
         return
      }
      XCTAssertNil(first.externalData)

      store?.downloadAssetsForOutwardObjects([first])

      awaitSync()

      context?.refresh(first, mergeChanges: false)
      XCTAssertEqual(first.externalData, testData)

   }
}
