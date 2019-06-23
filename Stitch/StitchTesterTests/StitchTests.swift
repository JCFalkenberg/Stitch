//
//  StitchTests.swift
//  StitchTesterTests
//
//  Created by Elizabeth Siemer on 6/20/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import XCTest
import Cocoa
@testable import Stitch

extension NSManagedObjectModel {
   /// The model will have a success and failure
   static var StitchTestsModel: NSManagedObjectModel = {
      let bundle = Bundle(for: StitchTests.self)
      guard let url = bundle.url(forResource: "TestModel", withExtension: "momd") else { return NSManagedObjectModel() }
      return NSManagedObjectModel(contentsOf: url) ?? NSManagedObjectModel()
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
      entity.name = NSStringFromClass(Entry.self)
      entity.managedObjectClassName = NSStringFromClass(Entry.self)

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

   func testTestModel() {
      let model = NSManagedObjectModel.StitchTestsModel
      XCTAssertEqual(model.configurations.count, 3)
      XCTAssert(model.configurations.contains("PF_DEFAULT_CONFIGURATION_NAME"))
      XCTAssert(model.configurations.contains("Success"))
      XCTAssert(model.configurations.contains("Failure"))
      XCTAssertEqual(model.entities.count, 7)
   }

   func validateAttribute(named: String) -> Bool {
      let backingAttributesModel = NSManagedObjectModel()
      let entity = NSEntityDescription("BadEntity", attributes:
         [NSAttributeDescription(named,
                                 optional: true,
                                 type: .stringAttributeType)]
      )
      backingAttributesModel.entities.append(entity)
      return backingAttributesModel.validateStitchStoreModel()
   }
   func validateEntity(named: String) -> Bool {
      let entityModel = NSManagedObjectModel()
      let entity = NSEntityDescription(named, attributes: [])
      entityModel.entities.append(entity)
      return entityModel.validateStitchStoreModel()
   }

   func testModelValidator() {
      let model = NSManagedObjectModel.StitchTestsModel
      XCTAssertTrue(model.validateStitchStoreModel(for: "Success"))
      XCTAssertFalse(model.validateStitchStoreModel(for: "Failure"))
      XCTAssertFalse(model.validateStitchStoreModel(for: "DoesntExist"))

      XCTAssertFalse(validateAttribute(named: NSEntityDescription.StitchStoreRecordIDAttributeName))
      XCTAssertFalse(validateAttribute(named: NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName))
      XCTAssertFalse(validateEntity(named: NSEntityDescription.StitchStoreChangeSetEntityName))
   }

   func testModifyModel() {
      let model = NSManagedObjectModel.StitchTestsModel
      let entity = model.entitiesByName[NSStringFromClass(Entry.self)]
      XCTAssertNotNil(entity)

      let backingModel = model.copyStichBackingModel(for: "Success")

      //Make sure our outward model is ok still
      XCTAssertEqual(model.entities.count, 7)
      XCTAssertEqual(entity?.managedObjectClassName, NSStringFromClass(Entry.self))
      XCTAssertNil(entity?.attributesByName[NSEntityDescription.StitchStoreRecordIDAttributeName])
      XCTAssertNil(entity?.attributesByName[NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName])

      XCTAssertEqual(backingModel.entities.count, 8)
      let backingEntity = backingModel.entitiesByName[NSStringFromClass(Entry.self)]!
      XCTAssertNotNil(backingEntity)
      XCTAssertEqual(backingEntity.managedObjectClassName, NSStringFromClass(NSManagedObject.self))
      XCTAssertNotNil(backingEntity.attributesByName[NSEntityDescription.StitchStoreRecordIDAttributeName])
      XCTAssertNotNil(backingEntity.attributesByName[NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName])

      XCTAssertNotNil(backingModel.entitiesByName[NSEntityDescription.StitchStoreChangeSetEntityName])
   }

   func testAddFailure() {
      let model = NSManagedObjectModel.StitchTestsModel
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
      do {
         let store = try coordinator.addPersistentStore(ofType: StitchStore.storeType,
                                                        configurationName: "Failure",
                                                        at: URL(fileURLWithPath: ""),
                                                        options: [ StitchStore.Options.BackingStoreType : NSInMemoryStoreType ])
         XCTAssertNil(store)
      } catch {
         if let error = error as? Stitch.StitchStore.StitchStoreError {
            switch error {
            case .invalidStoreModelForConfiguration:
               XCTAssertTrue(true)
            default:
               XCTFail("The wrong error was thrown for the above store add attempt")
            }
         } else {
            XCTFail("The wrong error was thrown for the above store add attempt")
         }
      }
   }

   func testAddStore() {
      let model = NSManagedObjectModel.StitchTestsModel
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
      do {
         let store = try coordinator.addPersistentStore(ofType: StitchStore.storeType,
                                                        configurationName: "Success",
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
