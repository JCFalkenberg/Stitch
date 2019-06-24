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
            StitchStore.Options.BackingStoreType: NSInMemoryStoreType,
            StitchStore.Options.ConnectionStatusDelegate: self,
            StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true)
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
         self.store = nil
      }
      coordinator = nil
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
   func addLocationAndSave() -> Location? {
      guard let context = context else {
         XCTFail("Context should not be nil")
         return nil
      }

      let location = Location(entity: Location.entity(), insertInto: context)
      location.displayName = "Home"

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

   func testAddObject() {
      let entry = addEntryAndSave()
      XCTAssertNotNil(entry)
      XCTAssertEqual(store?.changesCount(store!.backingMOC), 1)

      guard let changeSets = store?.insertedAndUpdatedChangeSets(store!.backingMOC) else {
         XCTFail("Change sets should not be nil!")
         return
      }
      XCTAssertEqual(changeSets.count, 1)
      let records = store?.ckRecords(for: changeSets)
      XCTAssertEqual(records?.count, 1)
      let text = records?.first?.value(forKey: "text") as? String
      XCTAssertNotNil(text)
      XCTAssertEqual(text, entry?.text)
      XCTAssertEqual(store?.deletedCKRecordIDs(store!.backingMOC).count, 0)
   }

   func testAddRelationship() {
      let entry = addEntryAndSave()
      let location = addLocationAndSave()

      entry?.location = location
      save()

      guard let changeSets = store?.insertedAndUpdatedChangeSets(store!.backingMOC) else {
         XCTFail("Change sets should not be nil!")
         return
      }
      XCTAssertEqual(changeSets.count, 3) //creation entry, creation location, add relationship to location
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

   func testFetchRelationship() {
      let entry = addEntryAndSave()
      let location = addLocationAndSave()

      entry?.location = location
      save()

      let request = NSFetchRequest<Entry>(entityName: "Entry")
      do {
         guard let results = try context?.fetch(request) else {
            XCTFail("nil results from fetch")
            return
         }
         XCTAssertEqual(results.count, 1)
         XCTAssertNotNil(results.first?.location)
         XCTAssertEqual(results.first?.location?.displayName, "Home")
      } catch {
         XCTFail("Error fetching results \(error)")
      }
   }

   func testReplacement() {
      guard let store = store else {
         XCTFail("No store!")
         return
      }

      guard let entry = addEntryAndSave() else {
         XCTFail("No entry!")
         return
      }
      let predicate = NSPredicate(format: "location == %@", entry)

      do {
         let replacedPredicate: NSPredicate? = try (predicate.copy() as! NSPredicate).predicateByReplacingManagedObjects(using: store)
         XCTAssert(replacedPredicate?.isKind(of: NSComparisonPredicate.self) ?? false)
         if let replacedPredicate = replacedPredicate as? NSComparisonPredicate {
            XCTAssertEqual(replacedPredicate.rightExpression.expressionType, .constantValue)
            XCTAssert(replacedPredicate.rightExpression.constantValue is NSManagedObject)
            if let object = replacedPredicate.rightExpression.constantValue as? NSManagedObject {
               XCTAssertEqual(object.entityName, "Entry")
               XCTAssertEqual(object.entity.managedObjectClassName, NSStringFromClass(NSManagedObject.self))
               XCTAssertNotNil(object[StitchStore.BackingModelNames.RecordIDAttribute])
            } else {
               XCTFail("Invalid object")
            }
         } else {
            XCTFail("Invalid predicate")
         }
      } catch {
         XCTFail("Error replacing predicate. \(error)")
      }
   }
   func testReplacementInAndContains() {
      guard let store = store else {
         XCTFail("No store!")
         return
      }

      guard let entry = addEntryAndSave(),
         let entry2 = addEntryAndSave() else {
            XCTFail("No entry!")
            return
      }

      let predicate = NSPredicate(format: "location in %@", [entry, entry2])
      let containsPredicate = NSPredicate(format: "%@ contains %@", [entry, entry2], entry)

      do {
         let replacedPredicate: NSPredicate? = try predicate.predicateByReplacingManagedObjects(using: store)
         XCTAssert(replacedPredicate?.isKind(of: NSComparisonPredicate.self) ?? false)

         let replacedContainsPredicate: NSPredicate? = try (containsPredicate.copy() as! NSPredicate).predicateByReplacingManagedObjects(using: store)
         XCTAssert(replacedContainsPredicate?.isKind(of: NSComparisonPredicate.self) ?? false)
      } catch {
         XCTFail("Error replacing predicate. \(error)")
      }
   }

   func testFetchReplacement() {
      let entry = addEntryAndSave()
      guard let location = addLocationAndSave() else {
         XCTFail("need location for this!")
         return
      }

      entry?.location = location
      save()
      let request = NSFetchRequest<Entry>(entityName: "Entry")
      request.predicate = NSPredicate(format: "location == %@ && text == %@", location, "be gay do crimes fk cops")
      do {
         guard let results = try context?.fetch(request) else {
            XCTFail("nil results from fetch")
            return
         }
         XCTAssertEqual(results.count, 1)
         XCTAssertNotNil(results.first?.location)
         XCTAssertEqual(results.first?.location?.displayName, "Home")
      } catch {
         XCTFail("Error fetching results \(error)")
      }

   }

   func testModifyObject() {
      let entry = addEntryAndSave()

      entry?.text = "be trans do crimes fk cops"

      save()
      XCTAssertEqual(store?.changesCount(store!.backingMOC), 2)
      guard let changeSets = store?.insertedAndUpdatedChangeSets(store!.backingMOC) else {
         XCTFail("Change sets should not be nil!")
         return
      }
      XCTAssertEqual(changeSets.count, 2)
      let records = store?.ckRecords(for: changeSets)
      XCTAssertEqual(records?.count, 1)
      let text = records?.first?.value(forKey: "text") as? String
      XCTAssertNotNil(text)
      XCTAssertEqual(text, entry?.text)
      XCTAssertEqual(store?.deletedCKRecordIDs(store!.backingMOC).count, 0)
   }

   func testDeleteObject() {
      guard let entry = addEntryAndSave() else {
         XCTFail("Unable to create entry")
         return
      }

      context?.delete(entry)

      save()
      XCTAssertEqual(store?.changesCount(store!.backingMOC), 2)
      XCTAssertEqual(store?.deletedCKRecordIDs(store!.backingMOC).count, 1)
   }
}
