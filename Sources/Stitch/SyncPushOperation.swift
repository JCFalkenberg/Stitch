//
//  File.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CloudKit

typealias SyncPushHandler = (Result<Bool, Error>) -> Void
typealias ModifyRecordsHandler = (Result<ModifyRecordsOperation, Error>) -> Void

class ModifyRecordsOperation: CKModifyRecordsOperation
{
   var handler: ModifyRecordsHandler
   var pushed: [CKRecord] = []
   var deleted: [CKRecord.ID] = []

   init(recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        database: CKDatabase?,
        handler: @escaping ModifyRecordsHandler)
   {
      self.handler = handler
      super.init()

      qualityOfService = .userInitiated
      savePolicy = .allKeys
      self.recordsToSave = recordsToSave
      self.recordIDsToDelete = recordIDsToDelete
      self.database = database

      self.modifyRecordsCompletionBlock = { (saved, deleted, error) in
         if let error = error {
            handler(.failure(error))
         } else {
            self.pushed = saved ?? []
            self.deleted = deleted ?? []
            handler(.success(self))
         }
      }
   }

}

class SyncPushOperation: AsyncOperation {

   var updates: [CKRecord]
   var deletes: [CKRecord.ID]
   var database: CKDatabase? = nil
   var handler: SyncPushHandler

   var pushError: Error? = nil
   var pushedUpdates: [CKRecord] = []
   var pushedDeletions: [CKRecord.ID] = []

   var backingOffOperations: Int = 0

   init(insertedOrUpdated: [CKRecord],
        deletedIDs: [CKRecord.ID],
        database: CKDatabase?,
        handler: @escaping SyncPushHandler)
   {
      self.updates = insertedOrUpdated
      self.deletes = deletedIDs
      self.handler = handler
      self.database = database
   }

   override func start() {
      super.start()

      queueOperation(recordsToSave: updates, recordIDsToDelete: deletes)
   }

   override func wrapUp() {
      if let error = pushError {
         handler(.failure(error))
      } else {
         handler(.success(true))
      }
      super.wrapUp()
   }

   func queueOperation(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID]) {
      let operation = ModifyRecordsOperation(recordsToSave: updates,
                                             recordIDsToDelete: deletes,
                                             database: database)
      { (result) in
         switch result {
         case .success(let operation):
            print("operation succeeded")
            self.pushedUpdates.append(contentsOf: operation.pushed)
            self.pushedDeletions.append(contentsOf: operation.deleted)
            self.checkProgress()
         case .failure(let error as NSError):
            print("operation failed \(error)")
            //If we are told too large, split in half and do it again
            if error.domain == CKErrorDomain &&
               error.code == CKError.limitExceeded.rawValue
            {
               self.splitAndReAddToQueue(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
            } else if error.domain == CKErrorDomain &&
               (error.code == CKError.requestRateLimited.rawValue || error.code == CKError.serviceUnavailable.rawValue)
            {
               self.backoff(recordsToSave: recordsToSave,
                            recordIDsToDelete: recordIDsToDelete,
                            seconds: (error as? CKError)?.retryAfterSeconds)
            } else {
               self.pushError = error
               self.wrapUp()
            }
         }
      }
      operationQueue.addOperation(operation)
   }

   func backoff(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID], seconds: Double?) {
      backingOffOperations += 1
      DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: DispatchTime.now() + .seconds(Int(seconds ?? 0.0))) {
         self.queueOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
         self.backingOffOperations -= 1
      }
   }

   func splitAndReAddToQueue(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID]) {
      let leftUpdates = Array(recordsToSave.prefix(upTo: recordsToSave.count/2))
      let rightUpdates = Array(recordsToSave.suffix(from: recordsToSave.count/2))
      let leftDeletes = Array(recordIDsToDelete.prefix(upTo: recordIDsToDelete.count/2))
      let rightDeletes = Array(recordIDsToDelete.suffix(from: recordIDsToDelete.count/2))
      queueOperation(recordsToSave: leftUpdates, recordIDsToDelete: leftDeletes)
      queueOperation(recordsToSave: rightUpdates, recordIDsToDelete: rightDeletes)
   }

   func checkProgress() {
      if operationQueue.operationCount == 0 &&
         pushedUpdates.count == updates.count &&
         pushedDeletions.count == deletes.count &&
         backingOffOperations == 0
      {
         wrapUp()
      }
   }
}
