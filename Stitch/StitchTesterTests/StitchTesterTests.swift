//
//  StitchTesterTests.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/20/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
import CoreData
@testable import Stitch

class StitchTesterTests: XCTestCase, StitchConnectionStatus {
   var model: NSManagedObjectModel = NSManagedObjectModel.StitchTestsModel
   var coordinator: NSPersistentStoreCoordinator? = nil
   var context: NSManagedObjectContext? = nil
   var store: StitchStore? = nil

   var internetConnectionAvailable: Bool { return false }

   override func setUp() {
      do {
         coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         let options: [String: Any] =  [
            StitchStore.Options.BackingStoreType : NSInMemoryStoreType,
            StitchStore.Options.ConnectionStatusDelegate : self
         ]
         store = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: "Success",
                                                     at: URL(fileURLWithPath: ""),
                                                     options: options) as? StitchStore
         XCTAssertNotNil(store)
         context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
         context?.persistentStoreCoordinator = coordinator
      } catch {
         XCTFail("There was an error adding the persistent store \(error)")
      }
   }

   override func tearDown() {
      // Put teardown code here. This method is called after the invocation of each test method in the class.
      context = nil
      if let store = store {
         try? coordinator?.remove(store)
      }
      coordinator = nil
   }

   func addEntryAndSave() -> Entry? {
      guard let context = context else {
         XCTFail("Context should not be nil")
         return nil
      }
      guard let entity = model.entitiesByName["Entry"] else {
         XCTFail("No entity!")
         return nil
      }

      let entry = Entry(entity: entity, insertInto: context)
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

   func testAddObject() {
      let entry = addEntryAndSave()
      XCTAssertNotNil(entry)
      XCTAssertEqual(store?.changesCount(), 1)

      guard let changeSets = store?.insertedAndUpdatedChangeSets() else {
         XCTFail("Change sets should not be nil!")
         return
      }
      XCTAssertEqual(changeSets.count, 1)
      let records = store?.ckRecords(for: changeSets)
      XCTAssertEqual(records?.count, 1)
      let text = records?.first?.value(forKey: "text") as? String
      XCTAssertNotNil(text)
      XCTAssertEqual(text, entry?.text)
      XCTAssertEqual(store?.deletedCKRecordIDs()?.count, 0)
   }

   func testFetch() {
      let _ = addEntryAndSave()

      let request = NSFetchRequest<Entry>(entityName: "Entry")
      do {
         guard let results = try context?.fetch(request) else {
            XCTFail("nil results from fetch")
            return
         }
         XCTAssertEqual(results.count, 1)
         XCTAssertEqual(results.first?.text, "be gay do crimes fk cops")
      } catch {
         XCTFail("Error fetching results \(error)")
      }
   }

   func testModifyObject() {
      let entry = addEntryAndSave()

      entry?.text = "be trans do crimes fk cops"

      save()
      XCTAssertEqual(store?.changesCount(), 2)
      guard let changeSets = store?.insertedAndUpdatedChangeSets() else {
         XCTFail("Change sets should not be nil!")
         return
      }
      XCTAssertEqual(changeSets.count, 2)
      let records = store?.ckRecords(for: changeSets)
      XCTAssertEqual(records?.count, 1)
      let text = records?.first?.value(forKey: "text") as? String
      XCTAssertNotNil(text)
      XCTAssertEqual(text, entry?.text)
      XCTAssertEqual(store?.deletedCKRecordIDs()?.count, 0)
   }

   func testDeleteObject() {
      guard let entry = addEntryAndSave() else {
         XCTFail("Unable to create entry")
         return
      }

      context?.delete(entry)

      save()
      XCTAssertEqual(store?.changesCount(), 2)
      XCTAssertEqual(store?.deletedCKRecordIDs()?.count, 1)
   }
}
