//
//  File.swift
//
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData
import CloudKit

@objc(Shelf)
class ChangeSet: NSManagedObject {
   @NSManaged public var sm_LocalStore_EntityName: String?
   @NSManaged public var sm_LocalStore_RecordID: String
   @NSManaged public var sm_LocalStore_ChangedProperties: String?
   @NSManaged public var sm_LocalStore_ChangeType: Int16
   @NSManaged public var sm_LocalStore_Queued: Bool

   public var changeType: StitchStore.RecordChange {
      get {
         return StitchStore.RecordChange(rawValue: sm_LocalStore_ChangeType) ?? .noChange
      }
      set {
         sm_LocalStore_ChangeType = newValue.rawValue
      }
   }
   public var recordID: String { return sm_LocalStore_RecordID }

   convenience init(context: NSManagedObjectContext,
                    entityName: String? = nil,
                    recordID: String,
                    changedProperties: String? = nil,
                    changeType: StitchStore.RecordChange)
   {
      self.init(entity: ChangeSet.entity(), insertInto: context)
      sm_LocalStore_EntityName = entityName
      sm_LocalStore_RecordID = recordID
      sm_LocalStore_ChangedProperties = changedProperties
      self.changeType = changeType
   }

   func ckRecord(zone: CKRecordZone.ID, existing: CKRecord? = nil) -> CKRecord? {
      guard let entityName = sm_LocalStore_EntityName else { return nil }
      let recordIDString = recordID
      let fetchRequest: NSFetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
      fetchRequest.predicate = NSPredicate(backingReferenceID: recordIDString)
      fetchRequest.fetchLimit = 1
      guard let object = (try? managedObjectContext?.fetch(fetchRequest).first) else { return nil }

      let changedPropertyKeys: [String]? = sm_LocalStore_ChangedProperties?.components(separatedBy: ",") ?? nil
      guard let record = object.updatedCKRecord(zone: zone, using: changedPropertyKeys) else { return nil }

      guard let existing = existing else { return record }
      for key in existing.allKeys() {
         if record[key] == nil {
            record.setObject(existing[key], forKey: key)
         }
      }
      return record
   }
}
