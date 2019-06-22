//
//  Stitch+Changesets
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

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
//      let changeSet = NSEntityDescription.insertNewObject(forEntityName: SMLocalStoreChangeSetEntityName, into: context)
//      let changedPropertyKeys = SMStoreChangeSetHandler.changedPropertyKeys(Array(object.changedValues().keys), entity: object.entity) + Array(object.entity.toOneRelationshipsByName().keys)
//      let recordIDString: String = object.value(forKey: SMLocalStoreRecordIDAttributeName) as! String
//      let changedPropertyKeysString = changedPropertyKeys.joined(separator: ",")
//      changeSet.setValue(recordIDString, forKey: SMLocalStoreRecordIDAttributeName)
//      changeSet.setValue(object.entity.name!, forKey: SMLocalStoreEntityNameAttributeName)
//      changeSet.setValue(changedPropertyKeysString, forKey: SMLocalStoreRecordChangedPropertiesAttributeName)
//      changeSet.setValue(NSNumber(value: SMLocalStoreRecordChangeType.recordUpdated.rawValue as Int16), forKey: SMLocalStoreChangeTypeAttributeName)
   }

   func createChangeSet(forDeleted recordID:String) {
//      let changeSet = NSEntityDescription.insertNewObject(forEntityName: SMLocalStoreChangeSetEntityName, into: backingContext)
//      changeSet.setValue(recordID, forKey: SMLocalStoreRecordIDAttributeName)
//      changeSet.setValue(NSNumber(value: SMLocalStoreRecordChangeType.recordDeleted.rawValue as Int16), forKey: SMLocalStoreChangeTypeAttributeName)
   }
}

