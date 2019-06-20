//
//  Stitch.swift
//  Stitch
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import CoreData
import CloudKit

public protocol StitchStoreConnectionStatus {
   var internetConnectionAvailable : Bool { get }
}

public let StitchStoreDidStartSyncOperationNotification = "StitchStoreDidStartSyncOperationNotification"
public let StitchStoreDidFailSyncOperationNotification = "StitchStoreDidFailSyncOperationNotification"
public let StitchStoreDidFinishSyncOperationNotification = "StitchStoreDidFinishSyncOperationNotification"

public let StitchStoreFetchRequestPredicateReplacementExperiment = "StitchStoreFetchRequestPredicateReplacementExperiment"
public let StitchStoreSyncConflictResolutionPolicyOption = "StitchStoreSyncConflictResolutionPolicyOption"
public let StitchStoreCloudKitContainerIdentifierOption = "StitchStoreCloudKitContainerIdentifierOption"
public let StitchStoreConnectionStatusDelegateOption = "StitchStoreConnectionStatusDelegateOption"
public let StitchStoreExcludedUnchangingAsyncAssetKeysOption = "StitchStoreExcludedUnchangingAsyncAssetKeys"
public let StitchStoreBackingStoreTypeOption = "StitchStoreBackingStoreTypeOption"
public let StitchStoreSyncOnSaveOption = "StitchStoreSyncOnSaveOption"

let StitchStoreErrorDomain = "StitchStoreErrorDomain"

public let StitchStoreLastSyncCompletedKey = "StitchStoreLastSyncCompletedKey"
public let StitchStoreChangedEntitiesToMigrate = "StitchStoreChangedEntitiesToMigrate"

class StitchStore: NSIncrementalStore {
   enum RecordChange: Int16 {
      case noChange = 0
      case updated  = 1
      case deleted  = 2
      case inserted = 3
   }

   public enum SyncTriggerType: Int {
      case push         = 0
      case storeAdded   = 1
      case networkState = 2
      case localSave    = 3

      var printName: String {
         let result: String
         switch self {
         case .push:
            result = "push notification"
         case .storeAdded:
            result = "store added"
         case .networkState:
            result = "network state"
         case .localSave:
            result = "local save"
         }

         return result
      }
   }

   public struct Notifications {
      public static let DidStartSync = Notification.Name(rawValue: StitchStoreDidStartSyncOperationNotification)
      public static let DidFailSync = Notification.Name(rawValue: StitchStoreDidFailSyncOperationNotification)
      public static let DidFinishSync = Notification.Name(rawValue: StitchStoreDidFinishSyncOperationNotification)
   }

   public struct Options {
      public static let FetchRequestPredicateReplacement = StitchStoreFetchRequestPredicateReplacementExperiment
      public static let SyncConflictResolutionPolicy = StitchStoreSyncConflictResolutionPolicyOption
      public static let CloudKitContainerIdentifier = StitchStoreCloudKitContainerIdentifierOption
      public static let ConnectionStatusDelegate = StitchStoreConnectionStatusDelegateOption
      public static let ExcludedUnchangingAsyncAssetKeys = StitchStoreExcludedUnchangingAsyncAssetKeysOption
      public static let BackingStoreType = StitchStoreBackingStoreTypeOption
      public static let SyncOnSave = StitchStoreSyncOnSaveOption
   }

   public struct Metadata {
      public static let LastSyncCompleted = StitchStoreLastSyncCompletedKey
      public static let ChangedEntitiesToMigrate = StitchStoreChangedEntitiesToMigrate
//      public static let SyncOperationServerToken = StitchStoreSyncOperationServerTokenKey

      public static let SetupFromBundleIDs = "StitchStoreSetupFromBundleIDs"
   }

   static public let storeType: String = {
      let type = NSStringFromClass(StitchStore.self)
      NSPersistentStoreCoordinator.registerStoreClass(StitchStore.self, forStoreType: type)
      return type
   }()

   fileprivate var operationQueue: OperationQueue = {
      let opQueue = OperationQueue()
      opQueue.maxConcurrentOperationCount = 1
      return opQueue
   }()

   @objc override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?,
                 configurationName name: String?,
                 at url: URL,
                 options: [AnyHashable: Any]?)
   {
      /* Do our initialization *before* the following */
      super.init(persistentStoreCoordinator: root, configurationName: name, at: url, options: options)
   }

   override func loadMetadata() throws {
//      metadata = ["Testing": "Hello"]
   }

   override open func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext?) throws -> Any {
      return []
   }

   override open func newValuesForObject(with objectID: NSManagedObjectID,
                                         with context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
      return NSIncrementalStoreNode()
   }
   override open func newValue(forRelationship relationship: NSRelationshipDescription,
                               forObjectWith objectID: NSManagedObjectID,
                               with context: NSManagedObjectContext?) throws -> Any
   {
      return []
   }
}
