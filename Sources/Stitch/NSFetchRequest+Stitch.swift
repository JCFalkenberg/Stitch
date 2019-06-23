//
//  NSFetchRequest+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

extension NSFetchRequest {
   @objc class func backingObjectRequest(for outwardObject: NSManagedObject, store: NSIncrementalStore) -> NSFetchRequest<NSManagedObject>? {
      guard let recordID = store.referenceObject(for: outwardObject.objectID) as? String else { return nil }
      let request = NSFetchRequest<NSManagedObject>(entityName: outwardObject.entityName)
      request.predicate = NSPredicate(backingReferenceID: recordID)
      request.fetchLimit = 1
      return request
   }

   @objc func transfer(to store: StitchStore) throws -> NSFetchRequest<NSFetchRequestResult> {
      guard let entityName = entityName else { throw StitchStore.StitchStoreError.invalidRequest }
      guard let entity = store.backingModel?.entitiesByName[entityName] else { throw StitchStore.StitchStoreError.invalidRequest }

      let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
      request.sortDescriptors = sortDescriptors
      request.resultType = resultType
      request.fetchLimit = fetchLimit
      request.fetchBatchSize = fetchBatchSize
      request.fetchOffset = fetchOffset
      request.affectedStores = [store.backingPersistentStore!]
      request.includesSubentities = includesSubentities
      request.includesPendingChanges = includesPendingChanges
      request.includesPropertyValues = includesPropertyValues
      request.returnsObjectsAsFaults = returnsObjectsAsFaults
      request.returnsDistinctResults = returnsDistinctResults
      if let properties = propertiesToFetch as? [NSPropertyDescription] {
         request.propertiesToFetch = store.backingModel?.backingProperties(for: properties, on: entity) ?? []
      }
      if let groupProperties = propertiesToFetch as? [NSPropertyDescription] {
         request.propertiesToGroupBy = store.backingModel?.backingProperties(for: groupProperties, on: entity) ?? []
      }
      request.shouldRefreshRefetchedObjects = shouldRefreshRefetchedObjects
      request.entity = entity

      if store.fetchPredicateReplacementOption, let predicate = predicate {
         request.predicate = try (predicate.copy() as! NSPredicate).predicateByReplacingManagedObjects(using: store)
      } else {
         request.predicate = predicate
      }
      return request
   }
}
