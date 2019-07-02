//
//  Stitch+Batch.swift
//  
//
//  Created by Elizabeth Siemer on 7/1/19.
//

import CoreData

extension StitchStore
{
   fileprivate func backingSyncIDs(for objectIDs: [NSManagedObjectID],
                                   on entity: String) throws -> [String]
   {
      let request = NSFetchRequest<NSDictionary>(entityName: entity)
      request.resultType = .dictionaryResultType
      request.propertiesToFetch = [BackingModelNames.RecordIDAttribute]
      request.predicate = NSPredicate(format: "self.objectID in %@", objectIDs)
      let results = try backingMOC.fetch(request)
      return results.compactMap { return $0[BackingModelNames.RecordIDAttribute] as? String }
   }

   func batchUpdate(_ request: NSBatchUpdateRequest,
                    context: NSManagedObjectContext) throws -> NSBatchUpdateResult
   {
      let cloneRequest = NSBatchUpdateRequest(entityName: request.entityName)
      cloneRequest.predicate = try request.predicate?.predicateByReplacingManagedObjects(using: self)
      cloneRequest.propertiesToUpdate = request.propertiesToUpdate?.filter {
         return ($0.key as? String) != BackingModelNames.RecordIDAttribute && ($0.key as? String) != BackingModelNames.RecordEncodedAttribute
      }
      cloneRequest.includesSubentities = request.includesSubentities
      cloneRequest.resultType = .updatedObjectIDsResultType

      guard let result = try backingMOC.executeBatch(cloneRequest) as? NSBatchUpdateResult,
         let results = result.result as? [NSManagedObjectID] else
      {
         throw StitchStoreError.invalidRequest
      }

      let syncIDs = try backingSyncIDs(for: results, on: request.entityName)
      let changedKeys: [String]? = cloneRequest.propertiesToUpdate?.compactMap {
         return $0.key as? String
      }
      let changedKeysString = changedKeys?.joined(separator: ",")
      for syncID in syncIDs {
         let _ = ChangeSet(context: backingMOC,
                           entityName: request.entityName,
                           recordID: syncID,
                           changedProperties: changedKeysString,
                           changeType: .updated)
      }

      let finalResult = NSManagedObjectContext.BatchUpdateResult(type: request.resultType)
      switch  request.resultType {
      case .statusOnlyResultType:
         finalResult.theResult = true
      case .updatedObjectIDsResultType:
         finalResult.theResult = results.map { outwardManagedObjectID($0) }
      case .updatedObjectsCountResultType:
         finalResult.theResult = results.count
      @unknown default:
         throw StitchStore.StitchStoreError.invalidRequest
      }
      return finalResult
   }

   func batchDelete(_ request: NSBatchDeleteRequest,
                    context: NSManagedObjectContext) throws -> NSBatchDeleteResult
   {
      let cloneFetch = try request.fetchRequest.transfer(to: self)
      let cloneRequest = NSBatchDeleteRequest(fetchRequest: cloneFetch)
      cloneRequest.resultType = .resultTypeObjectIDs

      let finalResult = NSManagedObjectContext.BatchDeleteResult(type: request.resultType)

      let objectIDRequest = cloneFetch.copy() as! NSFetchRequest<NSManagedObjectID>
      objectIDRequest.resultType = .managedObjectIDResultType

      let results = try backingMOC.fetch(objectIDRequest)

      if request.resultType == .resultTypeObjectIDs {
         finalResult.theResult = results.map { outwardManagedObjectID($0) }
      }

      let syncIDs = try backingSyncIDs(for: results, on: objectIDRequest.entityName!)

      guard let result = try backingMOC.executeBatch(cloneRequest) as? NSBatchDeleteResult,
         let batchresults = result.result as? [NSManagedObjectID] else
      {
         throw StitchStoreError.invalidRequest
      }

      for string in syncIDs {
         createChangeSet(forDeleted: string)
      }

      switch  request.resultType {
      case .resultTypeStatusOnly:
         finalResult.theResult = true
      case .resultTypeObjectIDs:
         break //handled above for reasons
      case .resultTypeCount:
         finalResult.theResult = batchresults.count
      @unknown default:
         throw StitchStore.StitchStoreError.invalidRequest
      }

      return finalResult
   }
}
