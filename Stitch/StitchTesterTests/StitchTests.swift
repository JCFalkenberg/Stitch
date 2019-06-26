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

   func testChangeTypeNames() {
      XCTAssertEqual(StitchStore.SyncTriggerType.localSave.printName, "local save")
      XCTAssertEqual(StitchStore.SyncTriggerType.networkState.printName, "network state")
      XCTAssertEqual(StitchStore.SyncTriggerType.storeAdded.printName, "store added")
      XCTAssertEqual(StitchStore.SyncTriggerType.push.printName, "push notification")
   }

   func testEntityModifier() {
      let entity = NSEntityDescription()
      entity.name = NSStringFromClass(Entry.self)
      entity.managedObjectClassName = NSStringFromClass(Entry.self)

      entity.modifyForStitchBackingStore()
      XCTAssertEqual(entity.managedObjectClassName, NSStringFromClass(NSManagedObject.self))
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.RecordIDAttribute])
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.RecordEncodedAttribute])
   }

   func testChangeSetEntity() {
      let entity = NSEntityDescription.changeSetEntity()
      XCTAssertEqual(entity.name, StitchStore.BackingModelNames.ChangeSetEntity)
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.RecordIDAttribute])
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.EntityNameAttribute])
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.ChangeTypeAttribute])
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.ChangedPropertiesAttribute])
      XCTAssertNotNil(entity.attributesByName[StitchStore.BackingModelNames.ChangeQueuedAttribute])
   }

   func testTestModel() {
      let model = NSManagedObjectModel.StitchTestsModel
      XCTAssertEqual(model.configurations.count, 3)
      XCTAssert(model.configurations.contains("PF_DEFAULT_CONFIGURATION_NAME"))
      XCTAssert(model.configurations.contains("Success"))
      XCTAssert(model.configurations.contains("Failure"))
      XCTAssertEqual(model.entities.count, 8)
   }

   func validateAttribute(named: String) -> Bool {
      let backingAttributesModel = NSManagedObjectModel()
      let entity = NSEntityDescription("BadEntity", attributes:
         [NSAttributeDescription(named,
                                 optional: true,
                                 type: .stringAttributeType)]
      )
      backingAttributesModel.entities.append(entity)
      backingAttributesModel.setEntities([entity], forConfigurationName: "Default")
      return backingAttributesModel.validateStitchStoreModel(for: "Default")
   }
   func validateEntity(named: String) -> Bool {
      let entityModel = NSManagedObjectModel()
      let entity = NSEntityDescription(named, attributes: [])
      entityModel.entities.append(entity)
      entityModel.setEntities([entity], forConfigurationName: "Default")
      return entityModel.validateStitchStoreModel(for: "Default")
   }

   func testModelValidator() {
      let model = NSManagedObjectModel.StitchTestsModel
      XCTAssertTrue(model.validateStitchStoreModel(for: "Success"))
      XCTAssertFalse(model.validateStitchStoreModel(for: "Failure"))
      XCTAssertFalse(model.validateStitchStoreModel(for: "DoesntExist"))

      XCTAssertFalse(validateAttribute(named: StitchStore.BackingModelNames.RecordIDAttribute))
      XCTAssertFalse(validateAttribute(named: StitchStore.BackingModelNames.RecordEncodedAttribute))
      XCTAssertFalse(validateEntity(named: StitchStore.BackingModelNames.ChangeSetEntity))
   }

   func testModifyModel() {
      let model = NSManagedObjectModel.StitchTestsModel
      let entity = model.entitiesByName[NSStringFromClass(Entry.self)]
      XCTAssertNotNil(entity)

      let backingModel = model.copyStichBackingModel(for: "Success")

      //Make sure our outward model is ok still
      XCTAssertEqual(model.entities.count, 8)
      XCTAssertEqual(entity?.managedObjectClassName, NSStringFromClass(Entry.self))
      XCTAssertNil(entity?.attributesByName[StitchStore.BackingModelNames.RecordIDAttribute])
      XCTAssertNil(entity?.attributesByName[StitchStore.BackingModelNames.RecordEncodedAttribute])

      XCTAssertEqual(backingModel.entities.count, 9)
      let backingEntity = backingModel.entitiesByName[NSStringFromClass(Entry.self)]!
      XCTAssertNotNil(backingEntity)
      XCTAssertEqual(backingEntity.managedObjectClassName, NSStringFromClass(NSManagedObject.self))
      XCTAssertNotNil(backingEntity.attributesByName[StitchStore.BackingModelNames.RecordIDAttribute])
      XCTAssertNotNil(backingEntity.attributesByName[StitchStore.BackingModelNames.RecordEncodedAttribute])

      XCTAssertNotNil(backingModel.entitiesByName[StitchStore.BackingModelNames.ChangeSetEntity])
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
