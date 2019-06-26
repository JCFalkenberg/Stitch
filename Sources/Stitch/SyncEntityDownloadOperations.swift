//
//  SyncEntityDownloadOperations.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CloudKit
import CoreData

extension CKError {
   var isBackoff: Bool {
      return code == .requestRateLimited || code == .zoneBusy
   }

   func backoffIfNeeded() -> Bool {
      if isBackoff {
         print("backing off upload due to \(code == .requestRateLimited ? "rate limit" : "busy zone")")
         sleep(UInt32(retryAfterSeconds ?? 2))
         return true
      }
      return false
   }
}

class EntityDownloadOperation: CKQueryOperation {
   var downloadedRecords = [CKRecord]()

   init(entityName: String,
        keysToSync: [String]?,
        database: CKDatabase?,
        zone: CKRecordZone.ID,
        cursor: CKQueryOperation.Cursor?,
        completion: @escaping ([CKRecord]?, CKQueryOperation.Cursor?, Error?) -> Void)
   {
      super.init()
      self.desiredKeys = keysToSync
      self.database = database
      self.zoneID = zone

      if let cursor = cursor {
         self.cursor = cursor
      } else {
         let query = CKQuery(recordType: entityName, predicate: NSPredicate(value: true))
         self.query = query
      }

      recordFetchedBlock = { [weak self] record in
         self?.downloadedRecords.append(record)
      }
      queryCompletionBlock = { [weak self] (cursor, error) in
         completion(self?.downloadedRecords.count ?? 0 > 0 ? self?.downloadedRecords : nil, cursor, error)
      }
   }
}

class EntityDownloadOperationWrapper: AsyncOperation {

   var entityName: String
   var downloadCompletionBlock: ([CKRecord]?, Error?) -> Void
   var downloadedRecords = [CKRecord]()
   var keysToSync: [String]?
   var database: CKDatabase?
   var zone: CKRecordZone.ID

   init(entityName: String,
        keysToSync: [String]?,
        database: CKDatabase?,
        zone: CKRecordZone.ID,
        completion: @escaping ([CKRecord]?, Error?) -> Void)
   {
      self.zone = zone
      self.database = database
      self.keysToSync = keysToSync
      self.entityName = entityName
      self.downloadCompletionBlock = completion
   }

   override func start() {
      super.start()
      downloadBatch(nil)
   }

   func downloadBatch(_ cursor: CKQueryOperation.Cursor?) {
      let batch = EntityDownloadOperation(entityName: entityName,
                                          keysToSync: keysToSync,
                                          database: database,
                                          zone: zone,
                                          cursor: cursor)
      { (records, cursor, error) in
         if let error = error as? CKError {
            if error.backoffIfNeeded() {
               self.downloadBatch(cursor)
            } else {
               print("Error downloading records: \(error)")
               self.downloadCompletionBlock(self.downloadedRecords.count > 0 ? self.downloadedRecords : nil, error)
               self.wrapUp()
            }
            return
         }
         if let records = records {
            self.downloadedRecords.append(contentsOf: records)
         }
         if let cursor = cursor {
            self.downloadBatch(cursor)
         } else {
            self.downloadCompletionBlock(self.downloadedRecords, nil)
            self.wrapUp()
         }
      }
      operationQueue.addOperation(batch)
   }
}

class MigrationDownloadOperation: AsyncOperation {
   var changedEntities: [String]

   var database: CKDatabase?
   var zone: CKRecordZone.ID
   var context: NSManagedObjectContext
   var keysToSync: [String]?

   var insertedOrUpdatedRecords = [CKRecord]()

   var completionHandler: ([NSManagedObjectID], [NSManagedObjectID], Error?) -> Void

   init(changed: [String],
        keysToSync: [String]?,
        database: CKDatabase?,
        zone: CKRecordZone.ID,
        context parent: NSManagedObjectContext,
        completion: @escaping ([NSManagedObjectID], [NSManagedObjectID], Error?) -> Void)
   {
      self.zone = zone
      self.database = database
      self.keysToSync = keysToSync
      self.changedEntities = changed

      self.context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
      self.context.parent = parent

      self.completionHandler = completion
      super.init()
   }

   /*
    * Basic flow:
    * Download new entity objects, and Redownload records for any changed entities
    * Integrate the results, make the connections
    */
   override func start() {
      super.start()

      for (index, entityName) in changedEntities.enumerated() {
         let operation = EntityDownloadOperationWrapper(entityName: entityName,
                                                        keysToSync: keysToSync,
                                                        database: database,
                                                        zone: zone)
         { (records, error) in
            if let records = records {
               self.insertedOrUpdatedRecords.append(contentsOf: records)
            }
            if index + 1 >= self.changedEntities.count {
               self.saveChanges()
            }
         }
         self.operationQueue.addOperation(operation)
      }
   }

   func saveChanges() {
      do {
         let results = try insertedOrUpdatedRecords.insertOrUpdate(into: context)
         try insertedOrUpdatedRecords.updateRecordReferences(in: context)
         try context.parent?.saveInBlockIfHasChanges()
         completionHandler(results.added, results.updated, nil)
      } catch {
         completionHandler([], [], error)
      }
      wrapUp()
   }
}
