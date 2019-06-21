//
//  StitchTests.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/20/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
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

   func testEntityModifier() {
      let entity = NSEntityDescription()
      entity.name = NSStringFromClass(TestEntry.self)
      entity.managedObjectClassName = NSStringFromClass(TestEntry.self)

      entity.modifyForStitchBackingStore()
      XCTAssertEqual(entity.managedObjectClassName, NSStringFromClass(NSManagedObject.self))
      XCTAssertNotNil(entity.attributesByName[NSEntityDescription.StitchStoreRecordIDAttributeName])
      XCTAssertNotNil(entity.attributesByName[NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName])
   }

   func testChangeSetEntity() {
      let entity = NSEntityDescription.changeSetEntity()
      XCTAssertEqual(entity.name, NSEntityDescription.StitchStoreChangeSetEntityName)
      XCTAssertNotNil(entity.attributesByName[NSEntityDescription.StitchStoreEntityNameAttributeName])
      XCTAssertNotNil(entity.attributesByName[NSEntityDescription.StitchStoreChangeTypeAttributeName])
      XCTAssertNotNil(entity.attributesByName[NSEntityDescription.StitchStoreRecordChangedPropertiesAttributeName])
      XCTAssertNotNil(entity.attributesByName[NSEntityDescription.StitchStoreChangeQueuedAttributeName])
   }

   func testModelValidator() {
      XCTAssertTrue(NSManagedObjectModel.StitchTestsModel.validateStitchStoreModel())
      //Need to implement the above
      //      XCTAssertFalse(NSManagedObjectModel.StitchTestFailModel.validateStitchStoreModel())
   }

   func testModifyModel() {
      class Entry: NSManagedObject {}
      let model = NSManagedObjectModel()
      let entity = NSEntityDescription()
      entity.name = NSStringFromClass(Entry.self)
      entity.managedObjectClassName = NSStringFromClass(Entry.self)
      model.entities.append(entity)

      let backingModel = model.copyStitchBackingModel()

      //Make sure our outward model is ok still
      XCTAssertEqual(model.entities.count, 1)
      XCTAssertEqual(entity.managedObjectClassName, NSStringFromClass(Entry.self))
      XCTAssertNil(entity.attributesByName[NSEntityDescription.StitchStoreRecordIDAttributeName])
      XCTAssertNil(entity.attributesByName[NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName])

      XCTAssertEqual(backingModel.entities.count, 2)
      XCTAssertNotNil(backingModel.entitiesByName[NSStringFromClass(Entry.self)])
      let backingEntity = backingModel.entitiesByName[NSStringFromClass(Entry.self)]!
      XCTAssertEqual(backingEntity.managedObjectClassName, NSStringFromClass(NSManagedObject.self))
      XCTAssertNotNil(backingEntity.attributesByName[NSEntityDescription.StitchStoreRecordIDAttributeName])
      XCTAssertNotNil(backingEntity.attributesByName[NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName])

      XCTAssertNotNil(backingModel.entitiesByName[NSEntityDescription.StitchStoreChangeSetEntityName])
   }

   func testAddStore() {
      let model = NSManagedObjectModel.StitchTestsModel
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
      do {
         let store = try coordinator.addPersistentStore(ofType: StitchStore.storeType,
                                                        configurationName: nil,
                                                        at: URL(fileURLWithPath: ""),
                                                        options: [ StitchStore.Options.BackingStoreType : NSInMemoryStoreType ])
         XCTAssertNotNil(store, "Store should not be nil, if there was an error creating the store it should have thrown it")
         XCTAssertEqual(store.type, StitchStore.storeType, "Store should be of type \(StitchStore.storeType)")
         XCTAssert(store.isKind(of: StitchStore.self), "Store should be of class StitchStore")
      } catch {
         XCTFail("There was an error adding the persistent store \(error)")
      }
   }
}
