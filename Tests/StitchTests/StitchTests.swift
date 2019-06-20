//
//  StitchTests.swift
//  Stitch
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import XCTest
import CoreData
@testable import Stitch

final class StitchTests: XCTestCase {
   override func setUp() {
      super.setUp()
   }

   func testStoreType() {
      // This is an example of a functional test case.
      // Use XCTAssert and related functions to verify your tests produce the correct
      // results.
      XCTAssertEqual(StitchStore.storeType, NSStringFromClass(StitchStore.self), "StitchStore's type should be StitchStore")
      XCTAssertNotNil(NSPersistentStoreCoordinator.registeredStoreTypes[StitchStore.storeType], "StitchStore not registered")
   }

   func testModelModifiers() {

   }

   func testAddStore() {
      let model = NSManagedObjectModel()
      let entity = NSEntityDescription()
      entity.name = "Entry"
      model.entities.append(entity)

      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
      do {
         let store = try coordinator.addPersistentStore(ofType: StitchStore.storeType,
                                                        configurationName: "Default",
                                                        at: URL(fileURLWithPath: "~/Desktop/Tests"),
                                                        options: [:])
         XCTAssertNotNil(store, "Store should not be nil, if there was an error creating the store it should have thrown it")
         XCTAssertEqual(store.type, StitchStore.storeType, "Store should be of type \(StitchStore.storeType)")
         XCTAssert(store.isKind(of: StitchStore.self), "Store should be of class StitchStore")
      } catch {
         XCTFail("There was an error adding the persistent store \(error)")
      }
   }
   
   static var allTests = [
      ("testStoreType", testStoreType),
      ("testAddStore", testAddStore),
   ]
}
