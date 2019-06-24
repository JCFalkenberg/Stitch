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

      resolve(inserted: insertedOrUpdated,
              deletedByType: deletedByType,
              localInserted: localInsertedOrUpdated,
              localDeleted: localDeletedIDs)
   }

   fileprivate func recordsByID(_ records: [CKRecord]) -> [CKRecord.ID: CKRecord] {
      var recordUpdatePairs = [CKRecord.ID: CKRecord]()
      for record in records {
         recordUpdatePairs[record.recordID] = record
      }
      return recordUpdatePairs
   }

   fileprivate func unconflictedFilter(_ unconflictedIDs: Set<CKRecord.ID>,
                                       inserted: [CKRecord.ID: CKRecord],
                                       deleted: Set<CKRecord.ID>) -> ([CKRecord], [CKRecord.ID])
   {
      var resolvedUpdates = [CKRecord]()
      var resolvedDeletedIDs = [CKRecord.ID]()
      for unconflictedID in unconflictedIDs {
         if let record = inserted[unconflictedID] {
            resolvedUpdates.append(record)
         }
         if deleted.contains(unconflictedID) {
            resolvedDeletedIDs.append(unconflictedID)
         }
      }
      return (resolvedUpdates, resolvedDeletedIDs)
   }

   fileprivate func resolve(inserted: [CKRecord],
                            deletedByType: [String: [CKRecord.ID]],
                            localInserted: [CKRecord],
                            localDeleted: [CKRecord.ID])
   {
      // server changes
      let serverInsertedPairs = recordsByID(inserted)
      let serverDeleted = Set(Array(deletedByType.values.joined()))
      let serverChangeIDs = Set(serverInsertedPairs.keys).union(serverDeleted)

      // local changes
      let localInsertedPairs = recordsByID(localInserted)
      let localDeleted = Set(localDeleted)
      let localChangeIDs = Set(localInsertedPairs.keys).union(localDeleted)

      // conflicted
      let conflictIDs = localChangeIDs.intersection(serverChangeIDs)

      // Server changes without conflicts
      let serverUnconflicted = unconflictedFilter(serverChangeIDs.subtracting(localChangeIDs),
                                                  inserted: serverInsertedPairs,
                                                  deleted: serverDeleted)
      var resolvedServerUpdates = serverUnconflicted.0
      var resolvedServerDeletedIDs = serverUnconflicted.1

      // Local changes without conflicts
      let localUnconflicted = unconflictedFilter(localChangeIDs.subtracting(serverChangeIDs),
                                                 inserted: localInsertedPairs,
                                                 deleted: localDeleted)
      var resolvedUpdates = localUnconflicted.0
      var resolvedDeletedIDs = localUnconflicted.1

      for conflictID in conflictIDs {
         let localUpdatedRecord = localInsertedPairs[conflictID]
         let serverUpdatedRecord = serverInsertedPairs[conflictID]

         let localDeleted = localDeleted.contains(conflictID)
         let serverDeleted = serverDeleted.contains(conflictID)

         switch self.conflictPolicy {
         case .clientWins:
            // Since there is a conflict, we know either local update or delete occured
            // as well as a server update or delete, keep the local, ignore the server
            if localDeleted {
               resolvedDeletedIDs.append(conflictID)
            } else if let localUpdatedRecord = localUpdatedRecord {
               resolvedUpdates.append(localUpdatedRecord)
            }
         case .serverWins:
            // Since there is a conflict, we know either local update or delete occured
            // as well as a server update or delete, keep the server ones, ignore the locals
            if serverDeleted {
               resolvedServerDeletedIDs.append(conflictID)
            } else if let serverUpdatedRecord = serverUpdatedRecord {
               resolvedServerUpdates.append(serverUpdatedRecord)
            }
         }
      }

      self.serverInsertedOrUpdated.append(contentsOf: resolvedServerUpdates)

      for deletedID in resolvedServerDeletedIDs {
         for (type, deletedIDs) in deletedByType {
            if deletedIDs.contains(deletedID) {
               if var deleted = self.serverDeletedRecordIDsByType[type] {
                  deleted.append(deletedID)
                  self.serverDeletedRecordIDsByType[type] = deleted
               } else {
                  self.serverDeletedRecordIDsByType[type] = [deletedID]
               }
            }
         }
      }

      resolvedPushUpdates(insertedOrUpdated: resolvedUpdates, deletedIDs: resolvedDeletedIDs)
   }

   fileprivate func resolvedPushUpdates(insertedOrUpdated: [CKRecord],
                                        deletedIDs: [CKRecord.ID])
   {
//      pushUpdateCount = insertedOrUpdated.count
//      pushDeleteCount = deletedIDs.count
//
//      recordUpdateIDsToPush = Set(insertedOrUpdated.map { $0.recordID })
//      recordDeleteIdsToPush = Set(deletedIDs)
//
//      if pushUpdateCount == 0 && pushDeleteCount == 0 {
//         saveMergedChanges()
//         return
//      }
//
//      self.pushOperations = PushChangesOperation.operationsForRecords(insertedOrUpdated: insertedOrUpdated,
//                                                                      deletedIDs: deletedIDs,
//                                                                      resolved: true,
//                                                                      database: self.database)
//      { (operation, error) in
//         if operation.conflicted.count > 0 && error == nil {
//            print("There shouldnt be conflicts here!")
//         } else if operation.conflicted.count == 0 && error == nil {
//            self.pushNextBatch()
//         } else {
//            //probably need to backoff, handle that somehow...
//            print("This would be a backoff error probably... \(error.debugDescription)")
//
//            if let error = error as? CKError, error.backoffIfNeeded() {
//               self.retryPush(operation)
//            } else {
//               print("Ok.... \(String(describing: error))")
//               //probably something horribly wrong has happened, and we should inform the UI of it
//            }
//         }
//      }
//      if self.pushOperations.count > 0 {
//         pushNextBatch()
//      } else {
//         print("No local changes to push!")
//         saveMergedChanges()
//      }
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
      if serverInsertedOrUpdated.count > 0 {
         let insertedOrUpdated = try serverInsertedOrUpdated.insertOrUpdate(into: syncContext)

         self.added.append(contentsOf: insertedOrUpdated.added)
         self.updated.append(contentsOf: insertedOrUpdated.updated)
      }
   }

   fileprivate func deleteManagedObjects() throws {
      if serverDeletedRecordIDsByType.count > 0 {
         let results = try serverDeletedRecordIDsByType.deleteRecords(in: syncContext)
         self.removed.append(contentsOf: results)
      }
   }

   fileprivate func updateRecordReferences() throws {
      if serverInsertedOrUpdated.count > 0 {
         try serverInsertedOrUpdated.updateRecordReferences(in: syncContext)
      }
   }
}
