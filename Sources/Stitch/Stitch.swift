//
//  Stitch.swift
//  Stitch
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import CoreData
import CloudKit

/// StitchConnectionStatus: A protocol for determining if we have an internet connection or not, this
@objc public protocol StitchConnectionStatus: NSObjectProtocol {
   /// internetConnectionAvailable: Bool, whether there is an internet connection available to sync on at the moment or not
   /// Can also be used to disable sync temporarily if needed for other reasons
   var internetConnectionAvailable : Bool { get }
}

/*
 The following are for Objective-C purposes only
 */
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

public let StitchStoreLastSyncCompletedKey = "SMStoreLastSyncCompletedKey"
public let StitchStoreChangedEntitiesToMigrate = "SMStoreChangedEntitiesToMigrate"

/// StitchStore: A CloudKit syncing NSIncrementalStore implementation
public class StitchStore: NSIncrementalStore {
   /// RecordChange: Enum used for tracking changes in the database in our backing store's extra enttiy for that
   internal enum RecordChange: Int16 {
      /// noChange: Unused, but if there was a reason to, this is what it would be in the DB field
      case noChange = 0
      /// updated: This record in the change log is an updated record
      case updated  = 1
      /// deleted: This record in the change log is a deleted record
      case deleted  = 2
      /// isnerted: This record in the change log is an inserted record
      case inserted = 3
   }

   /// SyncTriggerType: used for logging and priority decision on sync
   /// At higher priorities a sync always happen
   public enum SyncTriggerType: Int {
      /// push: we are syncing in response to a push notification, we  must sync if there is network connection
      case push         = 0
      /// storeAdded: we are syncing in response to adding the store, we should sync if there is a network connection
      case storeAdded   = 1
      /// networkState: the network state has changed to be available, we should sync if there is anything to sync up
      case networkState = 2
      /// localSave: only sync if we have changes to sync, not all saves will nesescarily produce changes to sync.
      case localSave    = 3

      /// Pretty print name for logging
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

   /// ConflictPolicy: Used to determine what to do when there are sync conflicts
   /// Default is serverWins
   enum ConflictPolicy: Int16 {
      /// clientDecides: Unused, will use a block call to determine the winner
//      case clientDecides = 0
      /// serverWins: Default. Server record wins when there is a conflict
      case serverWins = 1
      /// clientWins: Local record beats server record when there is a conflict
      case clientWins = 2
   }

   enum StitchStoreError: Error {
      case missingBackingPersistentStoreError
      case missingBackingContextError
      case backingStoreFetchRequestError
      case invalidRequest
      case invalidBackingStoreType
      case invalidStoreModelForConfiguration
      case invalidReferenceObject
      case errorCreatingStoreDirectory(underlyingError: NSError?)
      case backingStoreCreationFailed(underlyingError: NSError?)
   }

   /// RecordResolutionBlock: Unused for future support for clientDecides ConflictPolicy
   typealias RecordResolutionBlock = (_ clientRecord:CKRecord,_ serverRecord:CKRecord) -> CKRecord

   /// Notifications that are sent at various points in the sync cycle.
   /// All notifications are dispatched on the main queue.
   public struct Notifications {
      /// DidStartSync: sent when a sync is first started
      public static let DidStartSync = Notification.Name(rawValue: StitchStoreDidStartSyncOperationNotification)
      /// DidFailSync: sent when a sync fails, userInfo contains the userInfo from the underlying sync error
      public static let DidFailSync = Notification.Name(rawValue: StitchStoreDidFailSyncOperationNotification)
      /// DidFinishSync: notification when a sync successfully completes.
      /// userInfo payload has NSInsertedObjectsKey, NSDeletedObjectsKey, NSUpdatedObjectsKey with arrays of managed object ID's for inserted, deleted, and updated objects
      public static let DidFinishSync = Notification.Name(rawValue: StitchStoreDidFinishSyncOperationNotification)
   }

   /// Options keys explicitly for Stitch Store.
   /// The backing store is passed the options dictionary as well, so other keys may work
   public struct Options {
      /// FetchRequestPredicateReplacement: NSNumber boolean that enables use of %@ options in NSFetchRequest's NSPredicate.
      /// Defaults to false
      public static let FetchRequestPredicateReplacement = StitchStoreFetchRequestPredicateReplacementExperiment
      /// SyncConflictResolutionPolicy is an NSNumber of the raw value of one of the options in StitchStore.ConflictPolicy.
      /// Defaults to StitchStore.ConflictPolicy.serverWins
      public static let SyncConflictResolutionPolicy = StitchStoreSyncConflictResolutionPolicyOption
      /// CloudKitContainerIdentifier is a String identifying which CloudKit container ID to use if your app uses an identifier which does not match your Bundle ID.
      /// Defaults to using CKContainer.default().privateCloudDatabase
      public static let CloudKitContainerIdentifier = StitchStoreCloudKitContainerIdentifierOption
      /// ConnectionStatusDelegate: an object which conforms to StitchConnectionStatus for asking whether we have an internet connection at the moment
      public static let ConnectionStatusDelegate = StitchStoreConnectionStatusDelegateOption
      /// ExcludedUnchangingAsyncAssetKeys is an array of Strings which indicate keys which should not be synced down during the main cycle due to being a large CKAsset
      /// Syncing down can be done later on request or demand based on application need
      /// Your asset containing properties should not overlap in name with other keys you want synced down to use this
      /// Defaults to nil
      public static let ExcludedUnchangingAsyncAssetKeys = StitchStoreExcludedUnchangingAsyncAssetKeysOption
      /// BackingStoreType is a string which defines what type of backing store is to be used. Defaults to NSSQLiteStoreType and testing is done against this type. Other stores may have issues.
      public static let BackingStoreType = StitchStoreBackingStoreTypeOption
      /// SyncOnSave an NSNumber boolean value for whether to automatically sync when the database is told to save.
      /// Defaults to true.
      public static let SyncOnSave = StitchStoreSyncOnSaveOption
   }

   /// Metadata keys for Stitch Store
   public struct Metadata {
      /// LastSyncCompleted:  Date object which tells when the database last finished a successfull sync
      public static let LastSyncCompleted = StitchStoreLastSyncCompletedKey
      /// ChangedEntitiesToMigrate: storing what entities will need migrating next time a sync cycle occurs
      public static let ChangedEntitiesToMigrate = StitchStoreChangedEntitiesToMigrate
      /// SyncOperationServerToken: CloudKit sync operation serialized token
//      public static let SyncOperationServerToken = StitchStoreSyncOperationServerTokenKey

      /// SetupFromBundleIDs: Metadata key showing up what bundle ID's have setup their notifications from CloudKit
      public static let SetupFromBundleIDs = "SMStoreSetupFromBundleIDs"
   }

   // Computed or lazily loaded variables
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

   @objc open var isSyncing : Bool {
      return operationQueue.operationCount > 0
   }

   var tokenURL: URL? {
      guard let storeURL = url else { return nil }
      return storeURL.appendingPathComponent("cloudKitToken")
   }

   lazy var backingMOC: NSManagedObjectContext = {
      var moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
      moc.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
      moc.retainsRegisteredObjects = true
      moc.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
      return moc
   }()

   var conflictPolicy: ConflictPolicy = ConflictPolicy.serverWins
   var database: CKDatabase?
   var backingModel: NSManagedObjectModel? = nil
   var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator?
   var backingPersistentStore: NSPersistentStore?
   var syncAutomatically: Bool = true
   var syncAgain: Bool = false
   var nextSyncReason: SyncTriggerType = .localSave
   var recordConflictResolutionBlock: RecordResolutionBlock? = nil
   var syncOnSave: Bool = true

   fileprivate var changedEntitesToMigrate = [String]()

   var excludedUnchangingAsyncAssetKeys = [String]()
   var keysToSync: [String]?
   var fetchPredicateReplacementOption: Bool = false

   weak open var connectionStatus : StitchConnectionStatus? = nil

   @objc override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?,
                       configurationName name: String?,
                       at url: URL,
                       options: [AnyHashable: Any]?)
   {
      guard let rooted = root else {
         super.init(persistentStoreCoordinator: root, configurationName: name, at: url, options: options)
         return
      }
      backingModel = rooted.managedObjectModel.copyStitchBackingModel()

      if let policyNumber = options?[Options.SyncConflictResolutionPolicy] as? NSNumber,
         let policy = ConflictPolicy(rawValue: policyNumber.int16Value)
      {
         conflictPolicy = policy
      }
      if let identifier = options?[Options.CloudKitContainerIdentifier] as? String {
         database = CKContainer(identifier: identifier).privateCloudDatabase
      }
      if database == nil {
         database = CKContainer.default().privateCloudDatabase
      }
      if let status = options?[Options.ConnectionStatusDelegate] as? StitchConnectionStatus {
         connectionStatus = status;
      }
      excludedUnchangingAsyncAssetKeys = options?[Options.ExcludedUnchangingAsyncAssetKeys] as? [String] ?? []
      if excludedUnchangingAsyncAssetKeys.count > 0 {
         keysToSync = rooted.managedObjectModel.syncKeysExcludingAssetKeys(excludedUnchangingAsyncAssetKeys)
      }
      if let fetchPredicateOption = options?[Options.FetchRequestPredicateReplacement] as? NSNumber,
         fetchPredicateOption.boolValue
      {
         fetchPredicateReplacementOption = true
      }
      if let sync = options?[Options.SyncOnSave] as? NSNumber, !sync.boolValue {
         syncOnSave = false
      }

      let storeType = options?[Options.BackingStoreType] as? String ?? NSSQLiteStoreType
      let storeURL = url.appendingPathComponent(url.lastPathComponent)
      guard let existingMetadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType,
                                                                                                at: storeURL,
                                                                                                options: options) else
      {
         super.init(persistentStoreCoordinator: rooted, configurationName: name, at: url, options: options)
         return
      }
      guard let existingHashes = existingMetadata[NSStoreModelVersionHashesKey] as? [String: Data] else {
         super.init(persistentStoreCoordinator: rooted, configurationName: name, at: url, options: options)
         return
      }
      for entity in backingModel?.entities ?? [] {
         guard let entityName = entity.name else { continue }
         if let existingHash = existingHashes[entityName] {
            if entity.versionHash != existingHash {
               print("new version for \(entityName)")
               changedEntitesToMigrate.append(entityName)
            }
         } else {
            print("new entity \(entityName)")
            changedEntitesToMigrate.append(entityName)
         }
      }

      super.init(persistentStoreCoordinator: rooted, configurationName: name, at: url, options: options)
   }

   override public func loadMetadata() throws {
      let storeType = options?[Options.BackingStoreType] as? String ?? NSSQLiteStoreType
      if !NSPersistentStoreCoordinator.registeredStoreTypes.keys.contains(storeType) {
         throw StitchStoreError.invalidBackingStoreType
      }
      guard let backingModel = backingModel else { throw StitchStoreError.backingStoreCreationFailed(underlyingError: nil) }
      if !backingModel.validateStitchStoreModel(for: configurationName) {
         throw StitchStoreError.invalidStoreModelForConfiguration
      }
      self.backingPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: backingModel)

      var storeURL: URL? = self.url
      let tokenURL = self.tokenURL
      if storeType != NSInMemoryStoreType {
         guard let baseURL = self.url else { throw StitchStoreError.backingStoreCreationFailed(underlyingError: nil) }

         storeURL = baseURL.appendingPathComponent(baseURL.lastPathComponent)
         do {
            try FileManager.default.createDirectory(at: baseURL,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
         } catch {
            let nserror = error as NSError
            throw StitchStoreError.errorCreatingStoreDirectory(underlyingError: nserror)
         }
      }

      do {
         self.backingPersistentStore = try self.backingPersistentStoreCoordinator?.addPersistentStore(ofType: storeType,
                                                                                                      configurationName: configurationName,
                                                                                                      at: storeURL,
                                                                                                      options: options)

         if let tokenURL = tokenURL,
            let diskMetadata = NSDictionary(contentsOf: tokenURL) as? [String : AnyObject]
         {
            metadata = diskMetadata
         } else {
            let uuid = ProcessInfo().globallyUniqueString
            metadata = [NSStoreUUIDKey : uuid]
            setMetadata(StitchStore.storeType, key: NSStoreTypeKey)
         }
         if let changed = metadata[Metadata.ChangedEntitiesToMigrate] as? [String], changed.count > 0 {
            if changedEntitesToMigrate.count > 0 {
               let changedSet = Set<String>(changed)
               let union = changedSet.union(changedEntitesToMigrate)
               changedEntitesToMigrate = Array(union)
            } else {
               changedEntitesToMigrate = changed
            }
         }
         self.setMetadata(changedEntitesToMigrate.count > 0 ? changedEntitesToMigrate : nil, key: Metadata.ChangedEntitiesToMigrate)

         self.identifier = metadata[NSStoreUUIDKey] as? String
      } catch {
         let nserror = error as NSError
         throw StitchStoreError.backingStoreCreationFailed(underlyingError: nserror)
      }
      return
   }

   func setMetadata(_ value: Any?, key: String) {
      metadata[key] = value
      guard let tokenURL = tokenURL else { return }
      let dictionary = NSDictionary(dictionary: metadata)
      dictionary.write(to: tokenURL, atomically: true)
      #if os(iOS)
      do {
         var resourceValues = URLResourceValues()
         resourceValues.isExcludedFromBackup = true
         var url = tokenURL()
         try url.setResourceValues(resourceValues)
      } catch {
         print("Error setting file not backed up \(error)");
      }
      #endif
   }

   public class func isOurPushNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
//      guard let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
//      if ckNotification.notificationType == CKNotification.NotificationType.recordZone {
//         guard let recordZoneNotification = CKRecordZoneNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
//         /// TODO: FIX ME
//         if recordZoneNotification.recordZoneID?.zoneName == "" {
//            return true
//         }
//      }
      return false
   }
   @objc public func handlePush(userInfo: [AnyHashable: Any]) {
      if StitchStore.isOurPushNotification(userInfo) {
         self.triggerSync(.push)
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
         syncAgain = true;
         return
      }
      if !(self.connectionStatus?.internetConnectionAvailable ?? false) {
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
   }

   fileprivate func setupStore(_ reason: SyncTriggerType) {
   }

   override public func execute(_ request: NSPersistentStoreRequest,
                                with context: NSManagedObjectContext?) throws -> Any
   {
      guard let context = context else { throw StitchStoreError.invalidRequest }
      var results: Any? = nil
      switch request.requestType {
      case .fetchRequestType:
         guard let request = request as? NSFetchRequest<NSFetchRequestResult> else { throw StitchStoreError.invalidRequest }
         results = try fetch(request, context: context)
      case .saveRequestType:
         guard let request = request as? NSSaveChangesRequest else { throw StitchStoreError.invalidRequest }
         results = try save(request, context: context)
      default: //In the future it would be nice to support batchUpdateRequestType and batchDeleteRequestType
         throw StitchStoreError.invalidRequest
      }

      return results ?? []
   }

   fileprivate func fetch(_ fetchRequest: NSFetchRequest<NSFetchRequestResult>,
                          context: NSManagedObjectContext) throws -> [Any]?
   {
      guard let request = fetchRequest.transfer(to: self) else { throw StitchStoreError.invalidRequest }

      var mappedResults = [AnyObject]()
      self.backingMOC.performAndWait { () -> Void in
         do {
            let resultsFromLocalStore = try self.backingMOC.fetch(request)
            if resultsFromLocalStore.count > 0 {
               for object in resultsFromLocalStore {
                  if let object = object as? NSManagedObject {
                     mappedResults.append(object.objectID)
                  } else if let objectID = object as? NSManagedObjectID {
                     mappedResults.append(objectID)
                  } else if let dictionary = object as? NSDictionary {
                     mappedResults.append(dictionary)
                  } else if let count = object as? NSNumber {
                     mappedResults.append(count)
                  }
               }
            }
         } catch {
            print("Error executing fetch request!")
         }
      }
      mappedResults = mappedResults.map{ (object: AnyObject) -> AnyObject in
         var result: AnyObject = object
         switch request.resultType {
         case .managedObjectResultType:
            if let object = object as? NSManagedObjectID {
               let outwardID = outwardManagedObjectID(object)
               result = context.object(with: outwardID)
            }
         case .managedObjectIDResultType:
            if let object = object as? NSManagedObjectID {
               result = outwardManagedObjectID(object)
            }
         default:
            result = object
         }
         return result
      }
      return mappedResults
   }

   fileprivate func save(_ request: NSSaveChangesRequest, context: NSManagedObjectContext) throws -> [Any] {
      let inserted = request.insertedObjects ?? Set<NSManagedObject>()
      try insertInBacking(inserted, mainContext: context)

      let updated = request.updatedObjects ?? Set<NSManagedObject>()
      try updateInBacking(updated)

      let deleted = request.deletedObjects ?? Set<NSManagedObject>()
      try deleteFromBacking(deleted, mainContext: context)

      try _updateReferences(sourceObjects: inserted.union(updated), mainContext: context)
      try backingMOC.saveInBlockIfHasChanges()
      if syncOnSave {
         self.triggerSync(.localSave)
      }
      return []
   }

   public override func referenceObject(for objectID: NSManagedObjectID) -> Any {
      return "\(super.referenceObject(for: objectID))"
   }

   override public func newValuesForObject(with objectID: NSManagedObjectID,
                                    with context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
      return NSIncrementalStoreNode()
   }
   override public func newValue(forRelationship relationship: NSRelationshipDescription,
                          forObjectWith objectID: NSManagedObjectID,
                          with context: NSManagedObjectContext?) throws -> Any
   {
      return []
   }

   func backingObject(for referenceString: String, entity: String) -> NSManagedObject? {
      do {
         let fetchRequest: NSFetchRequest = NSFetchRequest<NSManagedObject>(entityName: entity)
         fetchRequest.predicate = NSPredicate(format: "%K == %@", NSEntityDescription.StitchStoreRecordIDAttributeName, referenceString)
         fetchRequest.fetchLimit = 1
         let results = try self.backingMOC.fetch(fetchRequest)
         return results.last
      } catch {
         print("Error retrieving objects in backing store")
      }
      return nil
   }

   fileprivate func outwardManagedObjectID(_ backingID: NSManagedObjectID) -> NSManagedObjectID {
      var recordID : String = ""
      var entityName : String = ""
      self.backingMOC.performAndWait { () -> Void in
         let value = self.backingMOC.object(with: backingID)
         recordID = value.value(forKey: NSEntityDescription.StitchStoreRecordIDAttributeName) as! String
         entityName = value.entity.name!
      }
      return outwardManagedObjectIDForRecordEntity(recordID, entityName: entityName)
   }
   fileprivate func outwardManagedObjectIDForRecordEntity(_ recordID: String, entityName: String) -> NSManagedObjectID {
      let entity = self.persistentStoreCoordinator!.managedObjectModel.entitiesByName[entityName]
      let objectID = self.newObjectID(for: entity!, referenceObject: recordID)
      return objectID
   }

   fileprivate func objectIDForBackingObjectForEntity(_ entityName: String, withReferenceObject referenceObject: String?) throws -> NSManagedObjectID? {
      guard let referenceObject = referenceObject else { return nil }
      let fetchRequest: NSFetchRequest = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
      fetchRequest.resultType = NSFetchRequestResultType.managedObjectIDResultType
      fetchRequest.fetchLimit = 1
      fetchRequest.predicate = NSPredicate(backingReferenceID: referenceObject)
      let results = try self.backingMOC.fetch(fetchRequest)
      return results.last
   }

   fileprivate func setRelationshipValues(for backingObject:NSManagedObject,
                                          sourceObject:NSManagedObject) throws
   {
   }

   fileprivate func _updateReferences(sourceObjects objects:Set<NSManagedObject>,
                                      mainContext: NSManagedObjectContext) throws
   {
   }

   fileprivate func insertInBacking(_ objects:Set<NSManagedObject>,
                                    mainContext: NSManagedObjectContext) throws
   {
      var caughtError: Error? = nil
      self.backingMOC.performAndWait({ () -> Void in
         for sourceObject in objects {
            let managedObject = NSEntityDescription.insertNewObject(forEntityName: (sourceObject.entity.name)!, into: self.backingMOC)
            let keys = Array(sourceObject.entity.attributesByName.keys)
            let dictionary = sourceObject.dictionaryWithValues(forKeys: keys)
            managedObject.setValuesForKeys(dictionary)

            guard let referenceObject: String = referenceObject(for: sourceObject.objectID) as? String else {
               caughtError = StitchStoreError.invalidReferenceObject
               break
            }
            managedObject.setValue(referenceObject, forKey: NSEntityDescription.StitchStoreRecordIDAttributeName)
            do {
               try backingMOC.obtainPermanentIDs(for: [managedObject])

//               SMStoreChangeSetHandler.createChangeSet(ForInsertedObjectRecordID: referenceObject,
//                                                       entityName: sourceObject.entity.name!,
//                                                       backingContext: backingMOC)
            } catch {
               caughtError = error
               print("Error inserting object in backing store \(error)")
               break
            }
         }
      })
      if let caughtError = caughtError {
         throw caughtError
      }
   }

   fileprivate func deleteFromBacking(_ objects: Set<NSManagedObject>,
                                      mainContext: NSManagedObjectContext) throws
   {
   }

   fileprivate func updateInBacking(_ objects: Set<NSManagedObject>) throws
   {
   }
}
