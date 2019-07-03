//
//  CloudKitSetupOperations.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CloudKit

public typealias BasicErrorCompletionBlock = (Result<Bool, Error>) -> Void

public extension CKModifySubscriptionsOperation {
   convenience init(create zoneID: CKRecordZone.ID,
                    name: String,
                    in database: CKDatabase?,
                    completion: @escaping BasicErrorCompletionBlock)
   {
      #if os(watchOS)
      let subscription = CKRecordZoneSubscription(zoneID: zoneID)
      #else
      let subscription = CKRecordZoneSubscription(zoneID: zoneID,
                                                  subscriptionID: name)
      #endif

      #if !os(watchOS)
      let subscriptionNotificationInfo = CKSubscription.NotificationInfo()
      #if !os(tvOS)
      subscriptionNotificationInfo.alertBody = ""
      subscriptionNotificationInfo.shouldSendContentAvailable = true
      subscriptionNotificationInfo.shouldBadge = false
      #endif
      subscription.notificationInfo = subscriptionNotificationInfo
      #endif

      self.init()
      subscriptionsToSave = [subscription]
      self.database = database
      self.qualityOfService = .userInitiated
      #if os(watchOS)
      self.__modifySubscriptionsCompletionBlock = { (modified, created, operationError) in
         if let error = operationError {
            completion(.failure(error))
         } else {
            completion(.success(true))
         }
      }
      #else
      self.modifySubscriptionsCompletionBlock = { (modified, created, operationError) in
         if let error = operationError {
            completion(.failure(error))
         } else {
            completion(.success(true))
         }
      }
      #endif
   }

   convenience init(delete zoneID: String,
                    in database: CKDatabase?,
                    completion: @escaping BasicErrorCompletionBlock)
   {
      #if os(watchOS)
      self.init()
      __subscriptionIDsToDelete = [zoneID]
      #else
      self.init(subscriptionsToSave: nil, subscriptionIDsToDelete: [zoneID])
      #endif
      self.database = database
      self.qualityOfService = .userInitiated
      #if os(watchOS)
      self.__modifySubscriptionsCompletionBlock = { (modified, created, operationError) in
         if let error = operationError {
            completion(.failure(error))
         } else {
            completion(.success(true))
         }
      }
      #else
      self.modifySubscriptionsCompletionBlock = { (modified, created, operationError) in
         if let error = operationError {
            completion(.failure(error))
         } else {
            completion(.success(true))
         }
      }
      #endif
   }
}


public extension CKModifyRecordZonesOperation {
   convenience init(create recordZone: CKRecordZone,
                    in database: CKDatabase?,
                    setupCompletion: @escaping BasicErrorCompletionBlock)
   {
      self.init(recordZonesToSave: [recordZone], recordZoneIDsToDelete: nil)
      self.database = database
      self.qualityOfService = .userInitiated
      self.modifyRecordZonesCompletionBlock = { (savedRecordZones, deletedRecordZonesIDs, operationError) in
         if let error = operationError {
            setupCompletion(.failure(error))
         } else {
            setupCompletion(.success(true))
         }
      }
   }

   convenience init(delete recordZone: CKRecordZone,
                    in database: CKDatabase?,
                    setupCompletion: @escaping BasicErrorCompletionBlock)
   {
      self.init(recordZonesToSave: nil, recordZoneIDsToDelete: [recordZone.zoneID])
      self.database = database
      self.qualityOfService = .userInitiated
      self.modifyRecordZonesCompletionBlock = { (savedRecordZones, deletedRecordZonesIDs, operationError) in
         if let error = operationError {
            setupCompletion(.failure(error))
         } else {
            setupCompletion(.success(true))
         }
      }
   }
}

