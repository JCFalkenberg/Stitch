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

   override func setUp() {
      guard let selector = invocation?.selector else {
         XCTFail("No invocation")
         return
      }
      zoneString = "StitchSyncTestsZone\(NSStringFromSelector(selector))"

      do {
         coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         let options: [String: Any] =  [
            StitchStore.Options.ConnectionStatusDelegate: self,
            StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true),
            StitchStore.Options.ZoneNameOption: zoneString!,
            StitchStore.Options.SubscriptionNameOption: zoneString!
         ]

         var storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
         storeURL.appendPathComponent("\(NSStringFromSelector(selector)).test")
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
   }

   var expectation: XCTestExpectation? = nil
   func syncNotification(_ note: Notification) {
      if note.name == StitchStore.Notifications.DidFinishSync {
         expectation?.fulfill()
      } else if note.name == StitchStore.Notifications.DidFailSync {
         XCTFail("Failed sync! \(String(describing: note.userInfo))")
         expectation?.fulfill()
      } else if note.name == StitchStore.Notifications.DidStartSync {
         print("started")
      } else {
         XCTFail("Unexpected sync note")
      }
   }

   func testStoreReady() {
      expectation = XCTestExpectation(description: "Sync Happened")
      store?.triggerSync(.storeAdded)

      guard let expectation = expectation else { return }
      wait(for: [expectation], timeout: 10.0)
   }
}
