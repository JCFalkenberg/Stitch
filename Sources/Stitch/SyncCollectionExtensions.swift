//
//  SyncCollectionExtensions.swift
//  
//
//  Created by Elizabeth Siemer on 6/24/19.
//

import CoreData
import CloudKit

extension Collection where Element == CKRecord {
   func insertOrUpdate(into context: NSManagedObjectContext) throws -> (added: [NSManagedObjectID], updated: [NSManagedObjectID])
   {
      var added = [NSManagedObjectID]()
      var updated = [NSManagedObjectID]()
      for record in self {
         let managedObject = try record.createOrUpdateManagedObject(in: context)
         if managedObject.isInserted {
            added.append(managedObject.objectID)
         } else {
            updated.append(managedObject.objectID)
         }
      }
      try context.saveInBlockIfHasChanges()
      return (added, updated)
   }

   func updateRecordReferences(in context: NSManagedObjectContext) throws {
      for record in self {
         guard let managedObject = try record.existingManagedObjectInContext(context) else { continue }
         let referencesValuesDictionary = try record.referencesAsManagedObjects(using: context)

         context.performAndWait {
            for (key, value) in referencesValuesDictionary {
               if let string = value as? String, string == StitchStore.CloudRecordNilValue {
                  managedObject[key] = nil
               } else {
                  managedObject[key] = value
               }
            }
         }
      }
      try context.saveInBlockIfHasChanges()
   }
}

extension Dictionary where Key == String, Value == [CKRecord.ID] {
   func deleteRecords(in context: NSManagedObjectContext) throws -> [(recordID: String, entityName: String)] {
      var removed = [(recordID: String, entityName: String)]()
//      let predicate = NSPredicate(format: "%K IN $ckRecordIDs", SMLocalStoreRecordIDAttributeName)
//      context.performAndWait({ () -> Void in
//         do {
//            for (type, recordIDs) in self {
//               let ckRecordIDStrings = recordIDs.map( { (object) -> String in
//                  let ckRecordID : CKRecord.ID = object
//                  return ckRecordID.recordName
//               })
//               let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: type)
//               fetchRequest.predicate = predicate.withSubstitutionVariables(["ckRecordIDs":ckRecordIDStrings])
//               let results = try context.fetch(fetchRequest)
//               for object in results {
//                  removed.append((recordID: object.value(forKey: SMLocalStoreRecordIDAttributeName) as! String, entityName: type))
//                  context.delete(object)
//               }
//            }
//         } catch {
//            print("error deleting managed objects")
//         }
//      })
//      context.saveInBlockIfHasChanges()
      return removed
   }
}

