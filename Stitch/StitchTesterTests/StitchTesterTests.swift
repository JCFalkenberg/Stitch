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

class TestEntry: NSManagedObject {}
extension NSManagedObjectModel {
   /*
    Make this a better model with actual things to validate
    */
   static var StitchTestsModel: NSManagedObjectModel = {
      var model = NSManagedObjectModel()
      let entity = NSEntityDescription()
      entity.name = NSStringFromClass(TestEntry.self)
      entity.managedObjectClassName = NSStringFromClass(TestEntry.self)
      model.entities.append(entity)
      return model
   }()

   /*
    A model with missing inverses and many to many relationships
    */
   static var StitchTestFailModel: NSManagedObjectModel = {
      var model = NSManagedObjectModel()
      let entity = NSEntityDescription()
      entity.name = NSStringFromClass(TestEntry.self)
      entity.managedObjectClassName = NSStringFromClass(TestEntry.self)
      model.entities.append(entity)
      return model
   }()
}

class StitchTesterTests: XCTestCase {
   var coordinator: NSPersistentStoreCoordinator? = nil
   var context: NSManagedObjectContext? = nil
   var store: StitchStore? = nil

   override func setUp() {
      do {
         let model = NSManagedObjectModel.StitchTestsModel
         coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
         let options =  [
            StitchStore.Options.BackingStoreType : NSInMemoryStoreType
         ]
         store = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: nil,
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

   func testAddObject() {
      // Use recording to get started writing UI tests.
      // Use XCTAssert and related functions to verify your tests produce the correct results.
   }
}
