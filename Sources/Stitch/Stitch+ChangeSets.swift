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
      let changedKeys = changedPropertyKeys(Array(object.changedValues().keys), entity: object.entity)
      let changedKeysString = changedKeys.joined(separator: ",")
      let recordIDString: String = object.value(forKey: NSEntityDescription.StitchStoreRecordIDAttributeName) as! String

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
}

