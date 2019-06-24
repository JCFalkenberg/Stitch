//
//  SyncOperation.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CoreData
import CloudKit

class AsyncOperation: Operation {
   override var isAsynchronous: Bool { return true }

   var _executing = false
   var _finished = false
   override var isFinished: Bool { return _finished }
   override var isExecuting: Bool { return _executing }

   var operationQueue: OperationQueue = {
      let opQueue = OperationQueue()
      opQueue.maxConcurrentOperationCount = 1
      return opQueue
   }()

   override func start() {
      willChangeValue(forKey: "isExecuting")
      _executing = true
      didChangeValue(forKey: "isExecuting")
   }

   func wrapUp() {
      willChangeValue(forKey: "isExecuting")
      _executing = false
      didChangeValue(forKey: "isExecuting")
      willChangeValue(forKey: "isFinished")
      _finished = true
      didChangeValue(forKey: "isFinished")
   }
}

struct SyncedObjects {
   let added: [NSManagedObjectID]
   let removed: [(recordID: String, entityName: String)]
   let updated: [NSManagedObjectID]
}
typealias SyncResultHandler = (Result<SyncedObjects, Error>) -> Void

class SyncOperation: AsyncOperation {
   fileprivate var startDate = Date()

   fileprivate var store: StitchStore
   fileprivate var syncContext: NSManagedObjectContext
   fileprivate var zoneID: CKRecordZone.ID
   fileprivate var keysToSync: [String]? = nil

   fileprivate var conflictPolicy: StitchStore.ConflictPolicy
   fileprivate var reason: StitchStore.SyncTriggerType
   fileprivate var database: CKDatabase?
   fileprivate var syncCompletionBlock: SyncResultHandler

   fileprivate var pushUpdateCount = 0
   fileprivate var pushDeleteCount = 0

//   fileprivate var pushOperations = [PushChangesOperation]()

   fileprivate var syncError: Error? = nil
   fileprivate var added = [NSManagedObjectID]()
   fileprivate var removed = [(recordID: String, entityName: String)]()
   fileprivate var updated = [NSManagedObjectID]()

   fileprivate var serverInsertedOrUpdated = [CKRecord]()
   fileprivate var serverDeletedRecordIDsByType = [String: [CKRecord.ID]]()

   fileprivate var recordUpdateIDsToPush = Set<CKRecord.ID>()
   fileprivate var recordDeleteIdsToPush = Set<CKRecord.ID>()

   init(store: StitchStore,
        reason: StitchStore.SyncTriggerType,
        completion: @escaping SyncResultHandler)
   {
      self.store = store
      keysToSync = store.keysToSync
      conflictPolicy = store.conflictPolicy
      self.reason = reason
      database = store.database
      zoneID = store.zoneID
      syncContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
      syncContext.parent = store.backingMOC
      syncCompletionBlock = completion
   }

   override func start() {
      super.start()

      if reason == .localSave && store.changesCount(syncContext) == 0 {
         print("Sync uneeeded in response to local save with no local changes to push")
         wrapUp()
         return
      }
      pullChanges()
   }

   override func wrapUp() {
      if let error = syncError {
         syncCompletionBlock(.failure(error))
      } else {
         syncCompletionBlock(.success(SyncedObjects(added: added,
                                                    removed: removed,
                                                    updated: updated)))
      }
      super.wrapUp()
   }

   fileprivate func pullChanges(filterUpdateIDs: Set<CKRecord.ID>? = nil,
                                filterDeleteIDs: Set<CKRecord.ID>? = nil)
   {
      let fetchOperation = FetchChangesOperation(changesFor: zoneID,
                                                 in: database,
                                                 previousToken: store.token(),
                                                 keysToSync: keysToSync)
      { (result) in
         switch result {
         case .success(let fetched):
            var filteredUpdated = fetched.changedInserted
            if let filterUpdateIDs = filterUpdateIDs, filterUpdateIDs.count > 0 {
               filteredUpdated = fetched.changedInserted.filter { !filterUpdateIDs.contains($0.recordID) }
            }

            var filteredDeleted = fetched.deletedByType
            if let filterDeleteIDs = filterDeleteIDs, filterDeleteIDs.count > 0 {
               filteredDeleted = [:]
               for (key, value) in fetched.deletedByType {
                  let filteredArray = value.filter {
                     filterDeleteIDs.contains($0)
                  }
                  if filteredArray.count == 0 { continue }
                  filteredDeleted[key] = filteredArray
               }
            }

            self.pulledChanges(insertedOrUpdated: filteredUpdated,
                               deletedByType: filteredDeleted,
                               newToken: fetched.token)
         case .failure(let error):
            self.syncError = error
            self.wrapUp()
         }
      }
      operationQueue.addOperation(fetchOperation)
   }

   fileprivate func pulledChanges(insertedOrUpdated: [CKRecord],
                                  deletedByType: [String: [CKRecord.ID]],
                                  newToken: CKServerChangeToken?)
   {
      store.saveToken(newToken)

      let localInsertedOrUpdated =  store.insertedAndUpdatedCKRecords(syncContext)
      let localDeletedIDs = store.deletedCKRecordIDs(syncContext)

      //If we don't have any pulled or local changes, were done!
      if localInsertedOrUpdated.count == 0 &&
         localDeletedIDs.count == 0 &&
         insertedOrUpdated.count == 0 &&
         deletedByType.values.joined().count == 0
      {
         saveMergedChanges()
         return
      }

      //If we don't have any local changes, we can go ahead to saveMergedChanges()
      if localInsertedOrUpdated.count == 0 &&
         localDeletedIDs.count == 0
      {
         self.serverInsertedOrUpdated = insertedOrUpdated
         self.serverDeletedRecordIDsByType = deletedByType
         saveMergedChanges()
         return
      }

      //No conflicts to resolve all changes local, push them up
      if insertedOrUpdated.count == 0 &&
         deletedByType.values.joined().count == 0
      {
         resolvedPushUpdates(insertedOrUpdated: localInsertedOrUpdated,
                             deletedIDs: localDeletedIDs)
      }

      // Ok, time to resolve updates
   }

   fileprivate func resolvedPushUpdates(insertedOrUpdated: [CKRecord],
                                        deletedIDs: [CKRecord.ID])
   {
   }

   fileprivate func saveMergedChanges() {
      do {
         try insertOrUpdateManagedObjects()
         try deleteManagedObjects()
         try updateRecordReferences()

         store.commitToken()

//         store.removeAllQueuedChangeSets(backingContext: self.backingContext)

         try syncContext.parent?.saveInBlockIfHasChanges()
         print("Sync Performed, took \(-startDate.timeIntervalSinceNow) seconds")
         wrapUp()
      } catch {
         print("Caught error trying to update our context")
         syncError = error
         wrapUp()
      }
   }

   fileprivate func insertOrUpdateManagedObjects() throws {
//      if serverInsertedOrUpdated.count > 0 {
//         let insertedOrUpdated = try serverInsertedOrUpdated.insertOrUpdate(into: backingContext)
//
//         self.added.append(contentsOf: insertedOrUpdated.added)
//         self.updated.append(contentsOf: insertedOrUpdated.updated)
//      }
   }

   fileprivate func deleteManagedObjects() throws {
//      if serverDeletedRecordIDsByType.count > 0 {
//         let results = try serverDeletedRecordIDsByType.deleteRecords(in: backingContext)
//         self.removed.append(contentsOf: results)
//      }
   }

   fileprivate func updateRecordReferences() throws {
//      if serverInsertedOrUpdated.count > 0 {
//         try serverInsertedOrUpdated.updateRecordReferences(in: backingContext)
//      }
   }
}
