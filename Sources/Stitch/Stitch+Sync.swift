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

   public typealias ZoneModifyCompletion = (_ zone: Bool, _ subscription: Bool, Error?) -> Void
   @objc open class func destroyZone(zone: CKRecordZone,
                                     in database: CKDatabase?,
                                     on queue: OperationQueue,
                                     completion: @escaping ZoneModifyCompletion)
   {
//      let deleteSubOperation = CKModifySubscriptionsOperation(delete: zone.zoneID.zoneName,
//                                                              in: database)
//      { (success, error) in
//         if success {
//            let deleteOperation = CKModifyRecordZonesOperation(delete: zone,
//                                                               in: database)
//            { (success, error) in
//               DispatchQueue.main.async {
//                  completion(success, true, error)
//               }
//            }
//            queue.addOperation(deleteOperation)
//         } else {
//            DispatchQueue.main.async {
//               completion(false, false, error)
//            }
//         }
//      }
//      queue.addOperation(deleteSubOperation)
   }

   open class func setupZone(zone: CKRecordZone,
                             in database: CKDatabase?,
                             on queue: OperationQueue,
                             completion: @escaping ZoneModifyCompletion)
   {
//      let setupOperation = CKModifyRecordZonesOperation(create: zone,
//                                                        in: database)
//      { (created, error) in
//         if created {
//            let subOperation = CKModifySubscriptionsOperation(create: zone.zoneID,
//                                                              in: database)
//            { (subCreated, error) in
//               completion(true , subCreated, error)
//            }
//            queue.addOperation(subOperation)
//         } else {
//            completion(false, false, error)
//         }
//      }
//      queue.addOperation(setupOperation)
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
         syncAgain = true;
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
//      let syncMachine = SyncingMachine(parentContext: backingMOC,
//                                       tokenHandler: tokenHandler,
//                                       keysToSync: keysToSync,
//                                       conflictPolicy: cksStoresSyncConflictPolicy,
//                                       reason: reason,
//                                       database: database,
//                                       zoneName: SMStoreCloudStoreCustomZoneName)
//      { (added, removed, updated, error) in
//         if let error = error as NSError? {
//            if error.domain == CKErrorDomain &&
//               error.code == CKError.changeTokenExpired.rawValue
//            {
//               print("Sync token out of date, delete and retry sync");
//               //Delete our token and retry sync
//               tokenHandler.delete()
//               DispatchQueue.main.async(execute: { () -> Void in
//                  triggerSync(reason);
//               });
//            } else {
//               print("Sync failed")
//               DispatchQueue.main.async { () -> Void in
//                  NotificationCenter.default.post(name: Notifications.DidFailSync, object: self, userInfo: error.userInfo)
//               }
//            }
//         } else {
//            setMetadata(Date() as AnyObject?, key: SMStoreLastSyncCompletedKey)
//            print("Sync Performed Successfully")
//            informSyncFinished(added: added,
//                                    removed: removed,
//                                    updated: updated)
//         }
//         DispatchQueue.global(qos: .default).async {
//            checkSyncAgain()
//         }
//      }
//      operationQueue.addOperation(syncMachine)

      DispatchQueue.main.async { () -> Void in
         NotificationCenter.default.post(name: Notifications.DidStartSync, object: self)
      }
   }

   internal func setupStore(_ reason: SyncTriggerType) {
      let recordZone = CKRecordZone(zoneName: zoneID.zoneName)
      StitchStore.setupZone(zone: recordZone,
                            in: database,
                            on: operationQueue)
      { (zone, subscription, error) in
         /* TO DO: ADD ERROR HANDLING */
         if zone {
            self.setMetadata(self.zoneID.zoneName, key: self.zoneID.zoneName)
         }
         if subscription {
            self.setMetadata(self.subscriptionName, key: self.subscriptionName)
         }

         if zone && subscription {
            var bundleIDs = self.metadata[Metadata.SetupFromBundleIDs] as? [String] ?? [String]()
            if let bundleIdentifier = Bundle.main.bundleIdentifier,
               !bundleIDs.contains(bundleIdentifier)
            {
               bundleIDs.append(bundleIdentifier)
               self.setMetadata(bundleIDs, key: "SMStoreSetupFromBundleIDs")
            }
         }
         self.syncStore(reason)
      }
   }

   fileprivate func checkSyncAgain() {
      if changedEntitesToMigrate.count > 0 {
         redownloadObjectsForMigratedEnttiies()
      } else if(syncAgain){
         let nextReason = nextSyncReason
         let delayTime = DispatchTime.now() + .seconds(1)
         syncAgain = false;
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
         guard let backingReference = referenceObject(for: object.objectID) as? String else { continue }
         if !downloadingAssets.contains(backingReference) {
            downloadingAssets.insert(backingReference)
            if var backingReferences = assetReferencesByType[entityName] {
               backingReferences.append(backingReference)
               assetReferencesByType[entityName] = backingReferences
            } else {
               assetReferencesByType[entityName] = [backingReference]
            }
         }
      }
      downloadBackingRecordsForReferences(assetReferencesByType)
   }

   internal func redownloadObjectsForMigratedEnttiies() {
//      let operation = MigrationDownloadOperation(changed: changedEntitesToMigrate,
//                                                 keysToSync: keysToSync,
//                                                 database: database,
//                                                 context: backingMOC)
//      { (added, updated, error) in
//         if let error = error {
//            print("error downloading migrated objects! \(error)")
//         } else {
//            /* if no error, remove the need to redo this from meta data */
//            informSyncFinished(added: added,
//                                    removed: [],
//                                    updated: updated)
//            DispatchQueue.main.async {
//               changedEntitesToMigrate.removeAll()
//               setMetadata(nil, key: SMStoreChangedEntitiesToMigrate)
//               checkSyncAgain()
//            }
//         }
//      }

//      operationQueue.addOperation(operation)
   }

   fileprivate func downloadBackingRecordsForReferences(_ referencesByType: [String: [String]]) {
      if !(connectionStatus?.internetConnectionAvailable ?? false) {
         return
      }

//      guard let database = database else { return }

//      let operations = CKFetchRecordsOperation.operationsToDownloadFullRecords(context: backingMOC,
//                                                                               for: referencesByType,
//                                                                               database: database)
//      { (recordIDs, finished) in
//         for outwardID in recordIDs {
//            if let backingReference = referenceObject(for: outwardManagedObjectID(outwardID)) as? String {
//               downloadingAssets.remove(backingReference)
//            }
//         }
//
//         informSyncFinished(added: recordIDs,
//                                 removed: [],
//                                 updated: [])
//
//         if finished {
//            DispatchQueue.main.async {
//               checkSyncAgain()
//            }
//         }
//      }
//      operationQueue.addOperations(operations, waitUntilFinished: false)
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
