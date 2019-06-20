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
   var model: NSManagedObjectModel? = nil
   var context: NSManagedObjectContext? = nil

   override func setUp() {
      super.setUp()
      do {
         model = NSManagedObjectModel()
         let entity = NSEntityDescription()
         entity.name = "Entry"
         model?.entities.append(entity)

         coordinator = NSPersistentStoreCoordinator(managedObjectModel: model!)
         let _ = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: "Default",
                                                     at: URL(fileURLWithPath: "~/Desktop/Testing"),
                                                     options: [:])
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
      XCTAssert(true, "Testing")
   }

   static var allTests = [
      ("testAddObject", testAddObject),
   ]
}
