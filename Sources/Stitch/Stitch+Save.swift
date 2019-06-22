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
         self.triggerSync(.localSave)
      }
      return []
   }

   /// _setRelationshipValues: ABSOLUTELY DO NOT CALL THIS EVER except  from updateReferences
   /// - Parameter backingObject: The backing object
   /// - Parameter sourceObject: the source object
   fileprivate func _setRelationshipValues(for backingObject: NSManagedObject) throws
   {
   }

   fileprivate func updateReferences(sourceObjects objects:Set<NSManagedObject>) throws
   {
   }

   fileprivate func insertInBacking(_ objects:Set<NSManagedObject>) throws
   {
      if objects.count == 0 { return }
      var caughtError: Error? = nil
      backingMOC.performAndWait({ () -> Void in
         for sourceObject in objects {
            let managedObject = NSEntityDescription.insertNewObject(forEntityName: (sourceObject.entity.name)!,
                                                                    into: self.backingMOC)
            let keys = Array(sourceObject.entity.attributesByName.keys)
            let dictionary = sourceObject.dictionaryWithValues(forKeys: keys)
            managedObject.setValuesForKeys(dictionary)

            guard let referenceObject: String = referenceObject(for: sourceObject.objectID) as? String else {
               caughtError = StitchStoreError.invalidReferenceObject
               break
            }
            managedObject.setValue(referenceObject, forKey: NSEntityDescription.StitchStoreRecordIDAttributeName)
            do {
               try backingMOC.obtainPermanentIDs(for: [managedObject])

               createChangeSet(forInserted: referenceObject,
                               entityName: sourceObject.entity.name!)
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
            guard let referenceObject: String = referenceObject(for: sourceObject.objectID) as? String else {
               caughtError = StitchStoreError.invalidReferenceObject
               break
            }
            let fetchRequest: NSFetchRequest = NSFetchRequest<NSManagedObject>(entityName: sourceObject.entity.name!)
            fetchRequest.predicate = NSPredicate(backingReferenceID: referenceObject)
            fetchRequest.fetchLimit = 1

            do {
               let results = try self.backingMOC.fetch(fetchRequest)
               guard let backingObject = results.last else { continue }
               createChangeSet(forDeleted: referenceObject)
               backingMOC.delete(backingObject)
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

            guard let referenceObject: String = referenceObject(for: sourceObject.objectID) as? String else {
               caughtError = StitchStoreError.invalidReferenceObject
               break
            }
            let fetchRequest: NSFetchRequest = NSFetchRequest<NSManagedObject>(entityName: sourceObject.entity.name!)
            fetchRequest.predicate = NSPredicate(backingReferenceID: referenceObject)
            fetchRequest.fetchLimit = 1

            do {
               let results = try self.backingMOC.fetch(fetchRequest)
               guard let backingObject = results.last else {
                  caughtError = StitchStoreError.invalidReferenceObject
                  break
               }
               let keys = Array(sourceObject.entity.attributesByName.keys)
               let sourceObjectValues = sourceObject.dictionaryWithValues(forKeys: keys)
               backingObject.setValuesForKeys(sourceObjectValues)

               createChangeSet(forUpdated: backingObject)
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
