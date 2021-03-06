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
         StitchStore.Options.ExcludedUnchangingAsyncAssetKeys: ["externalData"],
         StitchStore.Options.CloudKitContainerIdentifier: CloudKitID,
         NSInferMappingModelAutomaticallyOption: NSNumber(value: true),
         NSMigratePersistentStoresAutomaticallyOption: NSNumber(value: true)
      ]
   }

   static let doesntNeedSetupBefore: [Selector] = [
      #selector(testSyncDown),
      #selector(testSyncDownRelationship),
      #selector(testSyncDownLarge),
      #selector(testAsyncDataDownload),
      #selector(testSingleModelUpgrade)
   ]

   static let doesntNeedTearDownAfter: [Selector] = [
   ]

   override func setUp() {
      super.setUp()
      internetConnectionAvailable = true
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

   func testReloadMetadataSuccess() {
      guard var metadata = store?.metadata,
         let url = store?.tokenURL else {
            XCTFail("Metadata and token url shouldnt be nil")
            return
      }
      metadata["TestingKey"] = "My Name is Inigo Montoya, You killed my father, prepare to die."
      let dictionary = NSDictionary(dictionary: metadata)
      dictionary.write(to: url, atomically: true)
      
      XCTAssert(store?.reloadMetadataFromDisk() ?? false)

      XCTAssertEqual(store?.metadata["TestingKey"] as? String, metadata["TestingKey"] as? String)
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

   func testSyncDownRelationship() {
      setupZone()
      let zone = CKRecordZone.ID(zoneName: zoneString!,
                                 ownerName: CKCurrentUserDefaultName)
      let locationRecordID = CKRecord.ID(recordName: UUID().uuidString,
                                         zoneID: zone)
      _ = pushRecords(records: [
         RecordInfo(type: "Entry",
                    info: ["location": CKRecord.Reference(recordID: locationRecordID,
                                                          action: .none)]),
         RecordInfo(type: "Location",
                    info: ["displayName": "A Test" as CKRecordValue],
                    recordID: locationRecordID)
         ])

      addStore()
      store?.triggerSync(.storeAdded)
      awaitSync()

      let fetch = Entry.fetchRequest() as NSFetchRequest<Entry>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1)
      guard let entry = results?.first else {
         XCTFail("hrm..")
         return
      }
      XCTAssertNotNil(entry.location)
      XCTAssertEqual(entry.location?.displayName, "A Test")
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
      
      _ = pushRecords(records: [RecordInfo(type: "AllTypes",
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

   func testEntityResync() {
      _ = addEntryAndSave()
      awaitSync()

      store?.changedEntitesToMigrate = ["Entry"]
      store?.redownloadObjectsForMigratedEnttiies()

      awaitSync()
   }

   func testSyncConflictServerWins() {
      guard let entry = addEntryAndSave() else {
         XCTFail("no entry! fail.")
         return
      }
      awaitSync()

      guard let record = try? store?.ckRecordForOutwardObject(entry) else {
         XCTFail("No record? Fail")
         return
      }
      _ = pushRecords(deletedIDs: [record.recordID])

      entry.text = "Oh hai, be gay due crimze"
      _ = addEntryAndSave()
      awaitSync()

      let fetch = Entry.fetchRequest() as NSFetchRequest<Entry>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1)
   }

   func testSyncConflictClientWins() {
      store?.conflictPolicy = .clientWins
      guard let entry = addEntryAndSave() else {
         XCTFail("no entry! fail.")
         return
      }
      awaitSync()

      guard let record = try? store?.ckRecordForOutwardObject(entry) else {
         XCTFail("No record? Fail")
         return
      }
      _ = pushRecords(deletedIDs: [record.recordID])

      entry.text = "Oh hai, be gay due crimze"
      _ = addEntryAndSave()
      awaitSync()

      let fetch = Entry.fetchRequest() as NSFetchRequest<Entry>
      let results = try? context?.fetch(fetch)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 2)
   }

   func testRequestProperties() {
      let entry = addEntryAndSave()
      awaitSync()

      let request = NSFetchRequest<NSDictionary>(entityName: "Entry")

      request.resultType = .dictionaryResultType
      request.propertiesToFetch = [Entry.entity().propertiesByName["text"] ?? "text"]

      let results = try? context?.fetch(request as NSFetchRequest<NSDictionary>)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1)
      XCTAssertEqual(results?.first?["text"] as? String, entry?.text)
   }
   func testPropertiesToGroupBy() {
      let entry = addEntryAndSave()
      awaitSync()

      let request = NSFetchRequest<NSDictionary>(entityName: "Entry")

      request.resultType = .dictionaryResultType
      request.propertiesToFetch = [Entry.entity().propertiesByName["text"] ?? "text"]
      request.propertiesToGroupBy = [Entry.entity().propertiesByName["text"] ?? "text"]

      let results = try? context?.fetch(request as NSFetchRequest<NSDictionary>)
      XCTAssertNotNil(results)
      XCTAssertEqual(results?.count, 1)
      XCTAssertEqual(results?.first?["text"] as? String, entry?.text)
   }

   func testMultipleSyncs() {
      _ = addEntryAndSave()
      store?.triggerSync(.push)
      awaitSync()
      awaitSync()
   }

   var remoteNotificationTestInfo: [String: Any] {
      return [
         "ck": [
            "ce": 1,
            "cid": "iCloud.com.darkchocolatesoftware.StitchTester",
            "fet": [
               "dbs": 1,
               "sid": store!.subscriptionName,
               "zid": store!.zoneID.zoneName
            ],
            "nid": "00b2651f-5e1c-483b-b041-e09cca13b330"
         ],
         "aps": [
            "alert": "",
            "content-available": 1
         ]
      ]
   }

   func testPushUserInfo() {
      //This is fragile
      //MARK: TODO: Fix these for other platforms
      #if os(macOS)
      XCTAssert(store?.isOurPushNotification(remoteNotificationTestInfo) ?? false)
      #endif
   }

   func testHandleUserInfo() {
      //This is fragile
      //MARK: TODO: Fix these for other platforms
      #if os(macOS)
      store?.handlePush(userInfo: remoteNotificationTestInfo)
      awaitSync()
      #endif
   }

   func testSingleModelUpgrade() {
      internetConnectionAvailable = false
      addStore()
      removeStore()

      let bundle = Bundle(for: StitchSyncSystemTests.self)
      guard let url = bundle.url(forResource: "TestModel",
                                 withExtension: "momd")?.appendingPathComponent("TestModel2.mom")
         else
      {
         XCTFail("didnt find model")
         return
      }
      addStore(url)
      XCTAssertEqual(store?.changedEntitesToMigrate.count, 1)
      XCTAssert(store?.changedEntitesToMigrate.elementsEqual(["Entry"]) ?? false)
      internetConnectionAvailable = true
      store?.triggerSync(.networkState)
      awaitSync() //Sync
      awaitSync() //Entity redownload
      let expectation = XCTestExpectation(description: "Expectation")
      DispatchQueue.main.async {
         XCTAssertEqual(self.store?.changedEntitesToMigrate.count, 0)
         expectation.fulfill()
      }
      wait(for: [expectation], timeout: 1.0)
   }

   func testDoubleUpgradeStore() {
      internetConnectionAvailable = false
      addStore()
      removeStore()

      let bundle = Bundle(for: StitchSyncSystemTests.self)
      guard let url2 = bundle.url(forResource: "TestModel",
                                  withExtension: "momd")?.appendingPathComponent("TestModel2.mom")
         else
      {
         XCTFail("didnt find model")
         return
      }
      addStore(url2)
      removeStore()

      guard let url3 = bundle.url(forResource: "TestModel",
                                  withExtension: "momd")?.appendingPathComponent("TestModel3.mom")
         else
      {
         XCTFail("didnt find model")
         return
      }
      addStore(url3)

      XCTAssertEqual(store?.changedEntitesToMigrate.count, 2)
      XCTAssert(store?.changedEntitesToMigrate.contains("Entry") ?? false)
      XCTAssert(store?.changedEntitesToMigrate.contains("Shelf") ?? false)
      internetConnectionAvailable = true
      store?.triggerSync(.networkState)
      awaitSync() //Sync
      awaitSync() //Entity redownload
      let expectation = XCTestExpectation(description: "Expectation")
      DispatchQueue.main.async {
         XCTAssertEqual(self.store?.changedEntitesToMigrate.count, 0)
         expectation.fulfill()
      }
      wait(for: [expectation], timeout: 1.0)
   }

}
