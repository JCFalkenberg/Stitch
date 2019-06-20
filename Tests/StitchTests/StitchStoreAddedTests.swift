//
//  StitchStoreAddedTests.swift
//  
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import XCTest
import CoreData
@testable import Stitch

final class StitchStoreAddedTests: XCTestCase {
   var coordinator: NSPersistentStoreCoordinator? = nil
   var context: NSManagedObjectContext? = nil

   override func setUp() {
      super.setUp()
      do {
         let model = NSManagedObjectModel.StitchTestsModel
         coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         let _ = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: nil,
                                                     at: URL(fileURLWithPath: ""),
                                                     options: nil)
         context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
         context?.persistentStoreCoordinator = coordinator
      } catch {
         XCTFail("There was an error adding the persistent store \(error)")
      }

   }

   override func tearDown() {
      super.tearDown()
   }

   func testAddObject() {
//      if let context = context {
//         let entry = TestEntry(entity: TestEntry.entity(), insertInto: context)
//         XCTAssertNotNil(entry)
//      } else {
//         XCTFail("Context should not be nil")
//      }
   }

   static var allTests = [
      ("testAddObject", testAddObject),
   ]
}
