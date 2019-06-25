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
      let subscription = CKRecordZoneSubscription(zoneID: zoneID,
                                                  subscriptionID: name)
      let subscriptionNotificationInfo = CKSubscription.NotificationInfo()
      #if !os(tvOS)
      subscriptionNotificationInfo.alertBody = ""
      subscriptionNotificationInfo.shouldSendContentAvailable = true
      subscriptionNotificationInfo.shouldBadge = false
      #endif
      subscription.notificationInfo = subscriptionNotificationInfo

      self.init(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
      self.database = database
      self.qualityOfService = .userInitiated;
      self.modifySubscriptionsCompletionBlock = { (modified, created, operationError) in
         if let error = operationError {
            completion(.failure(error))
         } else {
            completion(.success(true))
         }
      }
   }

   convenience init(delete zoneID: String,
                    in database: CKDatabase?,
                    completion: @escaping BasicErrorCompletionBlock)
   {
      self.init(subscriptionsToSave: nil, subscriptionIDsToDelete: [zoneID])
      self.database = database
      self.qualityOfService = .userInitiated
      self.modifySubscriptionsCompletionBlock = { (modified, created, operationError) in
         if let error = operationError {
            completion(.failure(error))
         } else {
            completion(.success(true))
         }
      }
   }
}


public extension CKModifyRecordZonesOperation {
   convenience init(create recordZone: CKRecordZone,
                    in database: CKDatabase?,
                    setupCompletion: @escaping BasicErrorCompletionBlock)
   {
      self.init(recordZonesToSave: [recordZone], recordZoneIDsToDelete: nil)
      self.database = database
      self.qualityOfService = .userInitiated;
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

