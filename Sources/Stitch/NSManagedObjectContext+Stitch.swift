//
//  NSManagedObjectContext+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

extension NSManagedObjectContext {
   var entitiesByName: [String: NSEntityDescription]? {
      return persistentStoreCoordinator?.managedObjectModel.entitiesByName
   }

   func saveIfHasChanges() throws {
      if self.hasChanges {
         try self.save()
      }
   }

   func saveInBlockIfHasChanges() throws {
      var caughtError: Error? = nil
      self.performAndWait {
         do {
            try self.saveIfHasChanges()
         } catch {
            caughtError = error
            print("error saving in block if has changes \(error)")
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
   }

   @available(iOS 13.0, tvOS 13.0, macOS 14.0, watchOS 6.0, *)
   class BatchInsertResult: NSBatchInsertResult {
      var theResult: Any? = nil
      var theType: NSBatchInsertRequestResultType
      override var result: Any? { return theResult }
      override var resultType: NSBatchInsertRequestResultType { return theType }

      init(type: NSBatchInsertRequestResultType) {
         self.theType = type
      }
   }

   class BatchUpdateResult: NSBatchUpdateResult {
      var theResult: Any? = nil
      var theType: NSBatchUpdateRequestResultType
      override var result: Any? { return theResult }
      override var resultType: NSBatchUpdateRequestResultType { return theType }

      init(type: NSBatchUpdateRequestResultType) {
         self.theType = type
      }
   }

   class BatchDeleteResult: NSBatchDeleteResult {
      var theResult: Any? = nil
      var theType: NSBatchDeleteRequestResultType
      override var result: Any? { return theResult }
      override var resultType: NSBatchDeleteRequestResultType { return theType }

      init(type: NSBatchDeleteRequestResultType) {
         self.theType = type
      }
   }


   internal func executeBatch(_ request: NSPersistentStoreRequest) throws -> NSPersistentStoreResult {
      var hasOnlySQLiteStores = true
      for store in persistentStoreCoordinator?.persistentStores ?? [] {
         if store.type != NSSQLiteStoreType { hasOnlySQLiteStores = false }
      }
      if hasOnlySQLiteStores {
         return try execute(request)
      }
      if #available(iOS 13.0, tvOS 13.0, macOS 14.0, watchOS 6.0, *),
         let batchInsertRequest = request as? NSBatchInsertRequest
      {
         return try _executeBatchInsert(batchInsertRequest)
      }
      if let batchUpdateRequest = request as? NSBatchUpdateRequest {
         return try _executeBatchUpdate(batchUpdateRequest)
      }
      if let batchDeleteRequest = request as? NSBatchDeleteRequest {
         return try _executeBatchDelete(batchDeleteRequest)
      }

      throw StitchStore.StitchStoreError.invalidRequest
   }

   @available(iOS 13.0, tvOS 13.0, macOS 14.0, watchOS 6.0, *)
   fileprivate func _executeBatchInsert(_ request: NSBatchInsertRequest) throws -> NSBatchInsertResult
   {
      guard let entity = persistentStoreCoordinator?.managedObjectModel.entitiesByName[request.entityName] else {
         throw StitchStore.StitchStoreError.invalidRequest
      }
      var results = [NSManagedObject]()
      for valuesDict in request.objectsToInsert ?? [[:]] {
         let result = NSManagedObject(entity: entity, insertInto: self)
         result.setValuesForKeys(valuesDict)
         results.append(result)
      }

      let finalResult = BatchInsertResult(type: request.resultType)
      switch request.resultType {
      case .statusOnly:
         finalResult.theResult = true
      case .objectIDs:
         finalResult.theResult = results.map { $0.objectID }
      case .count:
         finalResult.theResult = results.count
      @unknown default:
         throw StitchStore.StitchStoreError.invalidRequest
      }
      return finalResult
   }

   fileprivate func _executeBatchUpdate(_ request: NSBatchUpdateRequest) throws -> NSBatchUpdateResult
   {
      let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: request.entityName)
      fetchRequest.predicate = request.predicate

      let objectsToChange = try fetch(fetchRequest)

      for object in objectsToChange {
         for (key, value) in request.propertiesToUpdate ?? [:] {
            if let key = key as? String {
               object[key] = value
            }
            if let key = key as? NSAttributeDescription {
               object[key.name] = (value as? NSExpression)?.constantValue
            }
         }
      }
      let result = BatchUpdateResult(type: request.resultType)

      switch request.resultType {
      case .statusOnlyResultType:
         result.theResult = true
      case .updatedObjectIDsResultType:
         result.theResult = objectsToChange.map { $0.objectID }
      case .updatedObjectsCountResultType:
         result.theResult = objectsToChange.count
      @unknown default:
         throw StitchStore.StitchStoreError.invalidRequest
      }
      return result
   }

   fileprivate func _executeBatchDelete(_ request: NSBatchDeleteRequest) throws -> NSBatchDeleteResult
   {
      let objectsToDelete = try fetch(request.fetchRequest)
      var objectIDs = [NSManagedObjectID]()
      for object in objectsToDelete {
         if let object = object as? NSManagedObject {
            delete(object)
            objectIDs.append(object.objectID)
         }
         if let id = object as? NSManagedObjectID {
            let object = self.object(with: id)
            delete(object)
            objectIDs.append(id)
         }
      }

      let result = BatchDeleteResult(type: request.resultType)

      switch request.resultType {
      case .resultTypeStatusOnly:
         result.theResult = true
      case .resultTypeObjectIDs:
         result.theResult = objectIDs
      case .resultTypeCount:
         result.theResult = objectsToDelete.count
      @unknown default:
         throw StitchStore.StitchStoreError.invalidRequest
      }
      return result
   }
}
