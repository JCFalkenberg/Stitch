//
//  SyncFetchOperation.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CloudKit
import CoreData

struct FetchedChanges {
   let changedInserted: [CKRecord]
   let deletedByType: [String: [CKRecord.ID]]
   let token: CKServerChangeToken?
}
typealias FetchRecordsCompletionBlock = (Result<FetchedChanges, Error>) -> Void

extension CKFetchRecordZoneChangesOperation.ZoneOptions {
   convenience init(token: CKServerChangeToken?,
                    keysToSync: [String]?)
   {
      self.init()
      self.previousServerChangeToken = token
      self.desiredKeys = keysToSync
   }
}

class FetchChangesOperation: CKFetchRecordZoneChangesOperation {
   fileprivate var modified = [CKRecord]()
   fileprivate var removedByType = [String: [CKRecord.ID]]()

   fileprivate var recordFetchingCompletion: FetchRecordsCompletionBlock

   fileprivate var latestToken: CKServerChangeToken?

   init(changesFor zoneID: CKRecordZone.ID,
        in database: CKDatabase?,
        previousToken: CKServerChangeToken?,
        keysToSync: [String]?,
        completion: @escaping FetchRecordsCompletionBlock)
   {
      latestToken = previousToken
      let options = CKFetchRecordZoneChangesOperation.ZoneOptions(token: previousToken,
                                                                  keysToSync: keysToSync)
      recordFetchingCompletion = completion
      super.init()
      self.database = database
      self.recordZoneIDs = [zoneID]
      self.optionsByRecordZoneID = [zoneID: options]

      self.recordChangedBlock = { [weak self] (record: CKRecord) in
         self?.modified.append(record)
      }
      self.recordWithIDWasDeletedBlock = { [weak self] (recordID, recordType) in
         if var deleted = self?.removedByType[recordType] {
            deleted.append(recordID)
            self?.removedByType[recordType] = deleted
         } else {
            self?.removedByType[recordType] = [recordID]
         }
      }

      self.recordZoneChangeTokensUpdatedBlock = { [weak self] (zoneID, token, clientChangeTokenData) in
         print("Token updated!")
         self?.latestToken = token
      }
      self.recordZoneFetchCompletionBlock = { [weak self] (zoneID, token, clientChangeTokenData, moreComing, error) in
         print("zone finished")
         self?.latestToken = token
      }

      self.fetchRecordZoneChangesCompletionBlock = { [weak self] (error) in
         if let error = error {
            print("All done fetching all zones! \(String(describing: error))")
            completion(.failure(error))
         } else {
            completion(.success(FetchedChanges(changedInserted: self?.modified ?? [],
                                               deletedByType: self?.removedByType ?? [:],
                                               token: self?.latestToken)))
         }
      }
   }
}
