//
//  StitchTesterTests.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/20/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
import CoreData
import CloudKit
@testable import Stitch

class StitchTesterTests: StitchTesterRoot {
   override var storeOptions: [String : Any] {
      return [
         StitchStore.Options.BackingStoreType: NSInMemoryStoreType,
         StitchStore.Options.ConnectionStatusDelegate: self,
         StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true)
      ]
   }

   override var internetConnectionAvailable: Bool { return false }

   override func setUp() {
      super.setUp()
      addStore()
   }

   override func tearDown() {
      removeStore()
      super.tearDown()
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
      XCTAssertEqual(changeSets.first?.changeType, StitchStore.RecordChange.inserted)
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

   func testQueueChanges() {
      _ = addEntryAndSave()

      XCTAssertEqual(store?.changesCount(store!.backingMOC), 1)
      store?.queueAllChangeSets(store!.backingMOC)
      XCTAssertEqual(store?.insertedAndUpdatedCKRecords(store!.backingMOC).count, 0)
      store?.dequeueAllChangeSets(store!.backingMOC)
      XCTAssertEqual(store?.insertedAndUpdatedCKRecords(store!.backingMOC).count, 1)
      store?.queueAllChangeSets(store!.backingMOC)
      XCTAssertEqual(store?.insertedAndUpdatedCKRecords(store!.backingMOC).count, 0)
      store?.removeAllQueuedChangeSets(store!.backingMOC)
      XCTAssertEqual(store?.changesCount(store!.backingMOC), 0)
      _ = addLocationAndSave()
      XCTAssertEqual(store?.changesCount(store!.backingMOC), 1)
   }

   func testAllTypes() {
      guard let context = context else {
         XCTFail("Context should not be nil")
         return
      }

      let testData = Data([0x61, 0x6e, 0x64, 0x61, 0x74, 0x61, 0x30, 0x31])

      let allTypes = AllTypes(entity: AllTypes.entity(), insertInto: context)
      allTypes.string = "be gay do crimes fk cops"
      allTypes.int16 = 16
      allTypes.int32 = 32
      allTypes.int64 = 64
      allTypes.decimal = NSDecimalNumber(floatLiteral: Double.pi)
      allTypes.float = Float.pi
      allTypes.boolean = true
      allTypes.double = Double.pi
      allTypes.binaryData = testData
      allTypes.externalData = testData
      allTypes.date = Date()

      save()

      do {
         let record = try store?.ckRecordForOutwardObject(allTypes)
         XCTAssertNotNil(record)

         XCTAssertEqual(record?.value(forKey: "string") as? String, "be gay do crimes fk cops")
         XCTAssertEqual((record?.value(forKey: "int16") as? NSNumber)?.int16Value, allTypes.int16)
         XCTAssertEqual((record?.value(forKey: "int32") as? NSNumber)?.int32Value, allTypes.int32)
         XCTAssertEqual((record?.value(forKey: "int64") as? NSNumber)?.int64Value, allTypes.int64)
         XCTAssertEqual((record?.value(forKey: "decimal") as? NSNumber)?.decimalValue, NSDecimalNumber(floatLiteral: Double.pi).decimalValue)
         XCTAssertEqual((record?.value(forKey: "float") as? NSNumber)?.floatValue, Float.pi)
         XCTAssertEqual((record?.value(forKey: "boolean") as? NSNumber)?.boolValue, true)
         XCTAssertEqual((record?.value(forKey: "double") as? NSNumber)?.doubleValue, Double.pi)
         XCTAssertEqual(record?.value(forKey: "binaryData") as? Data, testData)
         XCTAssert(record?.value(forKey: "externalData") is CKAsset)
         if let url = (record?.value(forKey: "externalData") as? CKAsset)?.fileURL,
            let externalData = try? Data(contentsOf: url)
         {
            XCTAssertEqual(externalData, testData)
         } else {
            XCTFail("Failed to read data)")
         }
         XCTAssertEqual(record?.value(forKeyPath: "date") as? Date, allTypes.date)

      } catch {
         XCTFail("Thrown error trying to get ckRecord \(error)")
      }
   }
}
