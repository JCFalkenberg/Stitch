//
//  Stitch+Changesets
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData
import CloudKit

extension StitchStore {
   func createChangeSet(forInserted recordID: String,
                        entityName: String)
   {
      let _ = ChangeSet(context: backingMOC,
                        entityName: entityName,
                        recordID: recordID,
                        changeType: .inserted)
   }

   func createChangeSet(forUpdated object: NSManagedObject) {
      let changedKeys = changedPropertyKeys(Array(object.changedValues().keys), entity: object.entity)
      let changedKeysString = changedKeys.joined(separator: ",")
      let recordIDString = object[NSEntityDescription.StitchStoreRecordIDAttributeName] as! String

      let _ = ChangeSet(context: backingMOC,
                        entityName: object.entity.name!,
                        recordID: recordIDString,
                        changedProperties: changedKeysString,
                        changeType: .updated)
   }


   func changedPropertyKeys(_ keys: [String], entity: NSEntityDescription) -> [String] {
      return keys.filter({ (key) -> Bool in
         let property = entity.propertiesByName[key]
         if let relationshipDescription = property as? NSRelationshipDescription {
            return relationshipDescription.isToMany == false
         }
         return true
      })
   }

   func createChangeSet(forDeleted recordID:String) {
      let _ = ChangeSet(context: backingMOC,
                        entityName: nil,
                        recordID: recordID,
                        changeType: .deleted)
   }

   func changesCount() -> Int {
      var result = 0
      backingMOC.performAndWait {
         let request = NSFetchRequest<NSNumber>(entityName: NSEntityDescription.StitchStoreChangeSetEntityName)
         request.resultType = .countResultType
         result = (try? backingMOC.fetch(request).first?.intValue) ?? 0
      }
      return result
   }

   func insertedAndUpdatedChangeSets() -> [ChangeSet] {
      var results: [ChangeSet] = []
      backingMOC.performAndWait {
         let request = NSFetchRequest<ChangeSet>(entityName: NSEntityDescription.StitchStoreChangeSetEntityName)
         request.predicate = NSPredicate(format: "(%K == %@ || %K == %@) && %K == %@",
                                         NSEntityDescription.StitchStoreChangeTypeAttributeName,
                                         NSNumber(value: RecordChange.inserted.rawValue),
                                         NSEntityDescription.StitchStoreChangeTypeAttributeName,
                                         NSNumber(value: RecordChange.updated.rawValue),
                                         NSEntityDescription.StitchStoreChangeQueuedAttributeName,
                                         NSNumber(value: false))
         results = (try? backingMOC.fetch(request)) ?? []
      }

      return results
   }

   func ckRecords(for changeSets: [ChangeSet]) -> [CKRecord] {
      var ckRecordsDict = [String: CKRecord]()

      for change in changeSets {
         if let existing = ckRecordsDict[change.recordID] {
            ckRecordsDict[change.recordID] = change.ckRecord(zone: zoneID, existing: existing)
         } else {
            ckRecordsDict[change.recordID] = change.ckRecord(zone: zoneID)
         }
      }

      return Array(ckRecordsDict.values)
   }

   func deletedCKRecordIDs() -> [CKRecord.ID]? {
      var recordIDs = [CKRecord.ID]()
      backingMOC.performAndWait {
         let request = NSFetchRequest<ChangeSet>(entityName: NSEntityDescription.StitchStoreChangeSetEntityName)
         request.predicate = NSPredicate(format: "%K == %@ && %K == %@",
                                         NSEntityDescription.StitchStoreChangeTypeAttributeName,
                                         NSNumber(value: RecordChange.deleted.rawValue),
                                         NSEntityDescription.StitchStoreChangeQueuedAttributeName,
                                         NSNumber(value: false))
         let results = (try? backingMOC.fetch(request)) ?? []
         for result in results {
            let ckRecordID = CKRecord.ID(recordName: result.recordID, zoneID: zoneID)
            recordIDs.append(ckRecordID)
         }
      }
      return recordIDs
   }
}

