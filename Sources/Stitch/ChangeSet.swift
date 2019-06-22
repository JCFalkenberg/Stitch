//
//  File.swift
//
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

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
}
