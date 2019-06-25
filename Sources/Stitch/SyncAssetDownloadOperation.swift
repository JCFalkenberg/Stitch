//
//  SyncAssetDownloadOperation.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CloudKit
import CoreData

struct AssetObjectReference {
   var entityName: String
   var backingReference: String
}

extension CKFetchRecordsOperation {
   class func operationsToDownloadFullRecords(context: NSManagedObjectContext,
                                              for references: [String: [String]],
                                              database: CKDatabase?,
                                              zone: CKRecordZone.ID,
                                              handler: @escaping ([NSManagedObjectID], Bool) -> Void) -> [CKFetchRecordsOperation]
   {
      let importContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType)
      importContext.parent = context

      var backingRecordIDs = [CKRecord.ID]()
      for (entityName, ids) in references {
         importContext.performAndWait {
            let fetchRequest: NSFetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
            fetchRequest.predicate = NSPredicate(format: "%K IN %@",
                                                 StitchStore.BackingModelNames.RecordIDAttribute,
                                                 ids)
            do {
               let backingObjects = try importContext.fetch(fetchRequest)
               let recordIDs = backingObjects.compactMap { $0.ckRecordID(zone: zone) }
               backingRecordIDs.append(contentsOf: recordIDs)
            } catch {
               print("error retrieving \(error)")
            }
         }
      }

      var results = [CKFetchRecordsOperation]()
      while backingRecordIDs.count > 0 {
         let finalOperation = backingRecordIDs.count > 200
         let ids = finalOperation ? Array(backingRecordIDs[0..<200]) : backingRecordIDs

         let updatedRecordsOperation = CKFetchRecordsOperation(recordIDs: ids)
         //set up the operation
         updatedRecordsOperation.qualityOfService = .userInitiated
         updatedRecordsOperation.database = database
         updatedRecordsOperation.fetchRecordsCompletionBlock =  { (recordsByRecordID, operationError) in
            guard let recordsByRecordID = recordsByRecordID else {
               handler([], finalOperation)
               return
            }

            var backingManagedObjectIDs = [NSManagedObjectID]()
            importContext.perform {
               for (_, record) in recordsByRecordID {
                  do {
                     let object = try record.createOrUpdateManagedObject(in: context)
                     backingManagedObjectIDs.append(object.objectID)
                  } catch {
                     print("error updating record \(error)")
                  }
               }
            }

            try? importContext.saveInBlockIfHasChanges()
            try? context.saveInBlockIfHasChanges()

            handler(backingManagedObjectIDs, finalOperation)
         }

         results.append(updatedRecordsOperation)
         backingRecordIDs.removeSubrange(0..<(backingRecordIDs.count > 200 ? 200 : backingRecordIDs.count))
      }
      return results
   }
}
