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
      #selector(testSyncDown)
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
}
