//
//  Stitch+Save.swift
//  
//
//  Created by Elizabeth Siemer on 6/22/19.
//

import CoreData

extension StitchStore {
   internal func save(_ request: NSSaveChangesRequest, context: NSManagedObjectContext) throws -> [Any] {
      let inserted = request.insertedObjects ?? Set<NSManagedObject>()
      try insertInBacking(inserted)

      let updated = request.updatedObjects ?? Set<NSManagedObject>()
      try updateInBacking(updated)

      let deleted = request.deletedObjects ?? Set<NSManagedObject>()
      try deleteFromBacking(deleted)

      try updateReferences(sourceObjects: inserted.union(updated))
      try backingMOC.saveInBlockIfHasChanges()
      if syncOnSave {
         triggerSync(.localSave)
      }
      return []
   }

   fileprivate func objectID(for entityName: String,
                             with referenceObject: String?) -> NSManagedObjectID?
   {
      guard let referenceObject = referenceObject else { return nil }
      let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
      request.resultType = .managedObjectIDResultType
      request.fetchLimit = 1
      request.predicate = NSPredicate(backingReferenceID: referenceObject)
      return try? backingMOC.fetch(request).last
   }

   /// _setRelationshipValues: ABSOLUTELY DO NOT CALL THIS EVER except  from updateReferences
   /// - Parameter backingObject: The backing object
   /// - Parameter sourceObject: the source object
   fileprivate func _setRelationshipValues(for backingObject: NSManagedObject, sourceObject: NSManagedObject)
   {
      for relationship in Array(sourceObject.entity.relationshipsByName.values) as [NSRelationshipDescription] {
         if relationship.isToMany { continue }
         guard let relationshipValue = sourceObject[relationship.name] as? NSManagedObject else {
            backingObject[relationship.name] = nil
            continue
         }
         if relationshipValue.objectID.isTemporaryID {
            continue
         }
         let reference = referenceObject(for: relationshipValue.objectID) as! String
         guard let backingRelatedID = objectID(for: relationship.destinationEntity!.name!,
                                               with: reference) else { continue }
         let backingRelatedObject = backingMOC.object(with: backingRelatedID)
         backingObject[relationship.name] = backingRelatedObject
      }
   }

   fileprivate func updateReferences(sourceObjects objects:Set<NSManagedObject>) throws
   {
      if objects.count == 0 { return }
      var caughtError: Error? = nil
      for sourceObject in objects {
         guard let request = NSFetchRequest<NSManagedObject>.backingObjectRequest(for: sourceObject,
                                                                                  store: self) else { continue }

         backingMOC.performAndWait {
            do {
               guard let result = try backingMOC.fetch(request).last else { return }
               _setRelationshipValues(for: result, sourceObject: sourceObject)
            } catch {
               print("Error \(error) updating references")
               caughtError = error
            }
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
   }

   fileprivate func insertInBacking(_ objects:Set<NSManagedObject>) throws
   {
      if objects.count == 0 { return }
      var caughtError: Error? = nil
      backingMOC.performAndWait({ () -> Void in
         for sourceObject in objects {
            let managedObject = NSEntityDescription.insertNewObject(forEntityName: (sourceObject.entity.name)!,
                                                                    into: backingMOC)
            let keys = Array(sourceObject.entity.attributesByName.keys)
            let dictionary = sourceObject.dictionaryWithValues(forKeys: keys)
            managedObject.setValuesForKeys(dictionary)

            guard let referenceObject: String = referenceObject(for: sourceObject.objectID) as? String else {
               caughtError = StitchStoreError.invalidReferenceObject
               break
            }
            managedObject[NSEntityDescription.StitchStoreRecordIDAttributeName] = referenceObject
            do {
               try backingMOC.obtainPermanentIDs(for: [managedObject])

               createChangeSet(forInserted: referenceObject,
                               entityName: sourceObject.entityName)
            } catch {
               caughtError = error
               print("Error inserting object in backing store \(error)")
               break
            }
         }
      })
      if let caughtError = caughtError {
         throw caughtError
      }
   }

   fileprivate func deleteFromBacking(_ objects: Set<NSManagedObject>) throws
   {
      if objects.count == 0 { return }
      var caughtError: Error? = nil
      backingMOC.performAndWait { () -> Void in
         for sourceObject in objects {
            guard let referenceObject = referenceObject(for: sourceObject.objectID) as? String else { continue }
            guard let request = NSFetchRequest<NSManagedObject>.backingObjectRequest(for: sourceObject,
                                                                                     store: self) else { continue }

            do {
               guard let result = try backingMOC.fetch(request).last else { continue }
               createChangeSet(forDeleted: referenceObject)
               backingMOC.delete(result)
            } catch {
               caughtError = error
               print("Error updating objects in backing store \(error)")
               break
            }
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
   }

   fileprivate func updateInBacking(_ objects: Set<NSManagedObject>) throws
   {
      if objects.count == 0 { return }
      var caughtError: Error? = nil
      backingMOC.performAndWait { () -> Void in
         for sourceObject in objects {
            if !sourceObject.hasPersistentChangedValues {
               continue
            }
            let modifiedKeys = sourceObject.changedValues().keys
            let toManyKeys = sourceObject.entity.relationshipsByName.compactMap { $0.value.isToMany ? $0.key : nil }
            if toManyKeys.count > 0 &&
               Set(modifiedKeys).intersection(Set(toManyKeys)) == Set(modifiedKeys)
            {
//               print("only modified too many relationships, skipping")
               continue
            }

            guard let request = NSFetchRequest<NSManagedObject>.backingObjectRequest(for: sourceObject,
                                                                                     store: self) else { continue }

            do {
               guard let result = (try self.backingMOC.fetch(request)).last else {
                  caughtError = StitchStoreError.invalidReferenceObject
                  break
               }
               let keys = Array(sourceObject.entity.attributesByName.keys)
               let sourceObjectValues = sourceObject.dictionaryWithValues(forKeys: keys)
               result.setValuesForKeys(sourceObjectValues)

               createChangeSet(forUpdated: result)
            } catch {
               caughtError = error
               print("Error updating objects in backing store \(error)")
               break
            }
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
   }
}
