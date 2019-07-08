//
//  Stitch+Sync.swift
//  
//
//  Created by Elizabeth Siemer on 6/23/19.
//

import CoreData
import CloudKit

extension StitchStore {
   func isOurPushNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
      guard let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
      if ckNotification.notificationType != CKNotification.NotificationType.recordZone { return false }
      guard let recordZoneNotification = CKRecordZoneNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
      return recordZoneNotification.recordZoneID?.zoneName == zoneID.zoneName
   }

   @objc public func handlePush(userInfo: [AnyHashable: Any]) {
      if isOurPushNotification(userInfo) {
         triggerSync(.push)
      }
   }

   /// triggerSync causes the database to run a sync cycle if an internet connection is available.
   /// Can be called automatically on save if the SMStore.Options.SyncOnSave flag is set in the options dictionary to true
   /// Will automatically queue up another sync cycle if a second call is made while a sync is in progress
   /// If called a third or more time while in the middle of a cycle, the highest priority reason for syncing will be used for the next sync cycle
   /// - Parameter reason: The reason for the sync, primarily used for logging and debug purposes, it is also used in the instance of SyncTriggerType. localSave to prevent a sync cycle from occuring with no queued changes.
   public func triggerSync(_ reason: SyncTriggerType) {
      if isSyncing {
         if reason.rawValue < nextSyncReason.rawValue {
            nextSyncReason = reason
         }
         syncAgain = true
         return
      }
      if !(connectionStatus?.internetConnectionAvailable ?? false) {
         return
      }

      print("Syncing in response to \(reason.printName)")

      /* ASSUMPTION! Bundle.main.bundleIdentifier isn't nil */
      if let bundleIDs = metadata[Metadata.SetupFromBundleIDs] as? [String],
         let currentBundleID = Bundle.main.bundleIdentifier,
         bundleIDs.contains(currentBundleID)
      {
         syncStore(reason)
      } else {
         setupStore(reason)
      }
   }

   fileprivate func syncStore(_ reason: SyncTriggerType) {
      backingMOC.performAndWait {
         backingMOC.reset()
      }
      let syncOperation = SyncOperation(store: self,
                                        reason: reason)
      { (result) in
         switch result {
         case .success(let syncedObjects):
            self.setMetadata(Date(), key: Metadata.LastSyncCompleted)
            self.informSyncFinished(added: syncedObjects.added,
                                    removed: syncedObjects.removed,
                                    updated: syncedObjects.updated)
         case .failure(let error as NSError):
            if error.domain == CKErrorDomain &&
               error.code == CKError.changeTokenExpired.rawValue
            {
               DispatchQueue.main.async {
                  self.deleteToken()
                  self.triggerSync(reason)
               }
            } else {
               DispatchQueue.main.async { () -> Void in
                  NotificationCenter.default.post(name: Notifications.DidFailSync, object: self, userInfo: nil)
               }
            }
         }
         DispatchQueue.main.async {
            self.checkSyncAgain()
         }
      }
      operationQueue.addOperation(syncOperation)

      DispatchQueue.main.async { () -> Void in
         NotificationCenter.default.post(name: Notifications.DidStartSync, object: self)
      }
   }

   public typealias ZoneModifyCompletion = (Result<(Bool), Error>) -> Void

   fileprivate func setupStore(_ reason: SyncTriggerType) {
      setupZone() { (result) in
         switch result {
         case .success(_):
            self.setMetadata(self.zoneID.zoneName, key: self.zoneID.zoneName)
            self.setMetadata(self.subscriptionName, key: self.subscriptionName)

            var bundleIDs = self.metadata[Metadata.SetupFromBundleIDs] as? [String] ?? [String]()
            if let bundleIdentifier = Bundle.main.bundleIdentifier,
               !bundleIDs.contains(bundleIdentifier)
            {
               bundleIDs.append(bundleIdentifier)
               self.setMetadata(bundleIDs, key: "SMStoreSetupFromBundleIDs")
            }
            self.syncStore(reason)
         case .failure(let error):
            DispatchQueue.main.async { () -> Void in
               NotificationCenter.default.post(name: Notifications.DidFailSync,
                                               object: self,
                                               userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
            }
         }
      }
   }

   fileprivate func setupZone(completion: @escaping ZoneModifyCompletion) {
      let recordZone = CKRecordZone(zoneName: zoneID.zoneName)
      let setupOperation = CKModifyRecordZonesOperation(create: recordZone,
                                                        in: database)
      { (result) in
         switch result {
         case .success(_):
            let subOperation = CKModifySubscriptionsOperation(create: recordZone.zoneID,
                                                              name: self.subscriptionName,
                                                              in: self.database,
                                                              completion: completion)
            self.operationQueue.addOperation(subOperation)
         case .failure(let error):
            completion(.failure(error))
         }
      }
      operationQueue.addOperation(setupOperation)
   }

   class func destroyZone(zone: CKRecordZone,
                          in database: CKDatabase?,
                          on queue: OperationQueue,
                          completion: @escaping ZoneModifyCompletion)
   {
      let deleteSubOperation = CKModifySubscriptionsOperation(delete: zone.zoneID.zoneName,
                                                              in: database)
      { (result) in
         switch result {
         case .success(_):
            let deleteOperation = CKModifyRecordZonesOperation(delete: zone,
                                                               in: database,
                                                               setupCompletion: completion)
            queue.addOperation(deleteOperation)
         case .failure(let error):
            completion(.failure(error))
         }
      }
      queue.addOperation(deleteSubOperation)
   }

   fileprivate func checkSyncAgain() {
      if changedEntitesToMigrate.count > 0 {
         redownloadObjectsForMigratedEnttiies()
      } else if(syncAgain){
         let nextReason = nextSyncReason
         let delayTime = DispatchTime.now() + .seconds(1)
         syncAgain = false
         DispatchQueue.main.asyncAfter(deadline: delayTime) {
            self.triggerSync(nextReason)
         }
         nextSyncReason = .localSave
      }
   }

   public func downloadAssetsForOutwardObjects(_ objects: [NSManagedObject]) {
      var assetReferencesByType = [String: [String]]()
      for object in objects {
         guard let entityName = object.entity.name else { continue }
         let backingReference = referenceString(for: object.objectID)
         guard !downloadingAssets.contains(backingReference) else { continue }

         downloadingAssets.insert(backingReference)
         if var backingReferences = assetReferencesByType[entityName] {
            backingReferences.append(backingReference)
            assetReferencesByType[entityName] = backingReferences
         } else {
            assetReferencesByType[entityName] = [backingReference]
         }
      }
      downloadBackingRecordsForReferences(assetReferencesByType)
   }

   internal func redownloadObjectsForMigratedEnttiies() {
      let operation = MigrationDownloadOperation(changed: changedEntitesToMigrate,
                                                 keysToSync: keysToSync,
                                                 database: database,
                                                 zone: zoneID,
                                                 context: backingMOC)
      { (added, updated, error) in
         if let error = error {
            print("error downloading migrated objects! \(error)")
         } else {
            /* if no error, remove the need to redo this from meta data */
            self.informSyncFinished(added: added,
                                    removed: [],
                                    updated: updated)
            DispatchQueue.main.async {
               self.changedEntitesToMigrate.removeAll()
               self.setMetadata(nil, key: Metadata.ChangedEntitiesToMigrate)
               self.checkSyncAgain()
            }
         }
      }

      operationQueue.addOperation(operation)
   }

   fileprivate func downloadBackingRecordsForReferences(_ referencesByType: [String: [String]]) {
      if !(connectionStatus?.internetConnectionAvailable ?? false) {
         return
      }

      guard let database = database else { return }

      let operations = CKFetchRecordsOperation.operationsToDownloadFullRecords(context: backingMOC,
                                                                               for: referencesByType,
                                                                               database: database,
                                                                               zone: zoneID)
      { (recordIDs, finished) in
         for outwardID in recordIDs {
            let backingReference = self.referenceString(for: self.outwardManagedObjectID(outwardID))
            self.downloadingAssets.remove(backingReference)
         }

         self.informSyncFinished(added: recordIDs,
                                 removed: [],
                                 updated: [])

         if finished {
            DispatchQueue.main.async {
               self.checkSyncAgain()
            }
         }
      }
      operationQueue.addOperations(operations, waitUntilFinished: false)
   }

   fileprivate func informSyncFinished(added: [NSManagedObjectID],
                                       removed: [(recordID: String, entityName: String)],
                                       updated: [NSManagedObjectID])
   {
      let userInfo = [
         NSInsertedObjectsKey : added.map { outwardManagedObjectID($0) },
         NSDeletedObjectsKey : removed.map { outwardManagedObjectIDForRecordEntity($0.recordID, entityName: $0.entityName) },
         NSUpdatedObjectsKey : updated.map { outwardManagedObjectID($0) }
      ]
      DispatchQueue.main.async {
         NotificationCenter.default.post(name: Notifications.DidFinishSync,
                                         object: self,
                                         userInfo: userInfo)
      }
   }
}
