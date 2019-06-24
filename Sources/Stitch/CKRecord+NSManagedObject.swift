//
//  CKRecord+NSManagedObject.swift
//  
//
//  Created by Elizabeth Siemer on 6/22/19.
//

import CoreData
import CloudKit

extension CKRecord {
   convenience init?(with encodedFields: Data) {
      let coder = NSKeyedUnarchiver(forReadingWith: encodedFields)
      self.init(coder: coder)
      coder.finishDecoding()
   }

   func encodedSystemFields() -> Data {
      let data = NSMutableData()
      let coder = NSKeyedArchiver(forWritingWith: data)
      encodeSystemFields(with: coder)
      coder.finishEncoding()
      return data as Data
   }

   func allReferencesKeys(using relationshipsByName: [String: NSRelationshipDescription]) -> [String] {
      return allKeys().filter { (key) -> Bool in
         return relationshipsByName[key] != nil
      }
   }

   func allAttributeKeys(using attributesByName: [String: NSAttributeDescription]) -> [String] {
      return allKeys().filter { (key) -> Bool in
         if let attribute = attributesByName[key] {
            return !attribute.isTransient
         }
         return false
      }
   }

   fileprivate func valuesForManagedObject(using context: NSManagedObjectContext) -> [String: AnyObject]?
   {
      guard let entity = context.entitiesByName?[recordType] else { return nil }
      var dictionary = dictionaryWithValues(forKeys: allAttributeKeys(using: entity.attributesByName))
      for (key, attribute) in entity.attributesByName {
         if attribute.isTransient {
            continue
         }
         if attribute.attributeType == .binaryDataAttributeType &&
            attribute.allowsExternalBinaryDataStorage
         {
            var data : Data? = nil
            if let asset = object(forKey: key) as? CKAsset,
               let url = asset.fileURL
            {
               if FileManager.default.fileExists(atPath: url.path){
                  data = try? Data(contentsOf: url)
               }
            }
            dictionary[key] = data
         }
      }
      return dictionary as [String : AnyObject]?
   }

   func existingManagedObjectInContext(_ context: NSManagedObjectContext) throws -> NSManagedObject? {
      guard context.entitiesByName?[recordType] != nil else {
         throw StitchStore.StitchStoreError.invalidReferenceObject
      }
      let fetchRequest = NSFetchRequest<NSFetchRequestResult>.backingObjectRequest(for: self)
      return try context.fetch(fetchRequest).last
   }

   func createOrUpdateManagedObject(in context: NSManagedObjectContext) throws -> NSManagedObject
   {
      guard let entity = context.entitiesByName?[recordType],
         let entityName = entity.name else {
            throw StitchStore.StitchStoreError.invalidReferenceObject
      }

      var managedObject = try existingManagedObjectInContext(context)
      if managedObject == nil {
         managedObject = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
      }

      guard let object = managedObject else {
         throw StitchStore.StitchStoreError.invalidReferenceObject
      }
      object[StitchStore.BackingModelNames.RecordIDAttribute] = recordID.recordName
      object[StitchStore.BackingModelNames.RecordEncodedAttribute] = encodedSystemFields()
      let attributeValuesDictionary = valuesForManagedObject(using: context)
      if let attributeValuesDictionary = attributeValuesDictionary {
         let allKeys = object.entity.attributesByNameSansBacking.keys
         for key in allKeys {
            object[key] = attributeValuesDictionary[key]
         }
      }
      return object
   }

   func referencesAsManagedObjects(using context: NSManagedObjectContext) throws -> [String: AnyObject]
   {
      guard let entity = context.entitiesByName?[recordType] else {
         throw StitchStore.StitchStoreError.invalidReferenceObject
      }
      let referenceKeys = allReferencesKeys(using: entity.toOneRelationshipsByName)
      let referencesValuesDictionary = dictionaryWithValues(forKeys: referenceKeys)
      var managedObjectsDictionary = [String: AnyObject]()
      
      for (key, value) in referencesValuesDictionary {
         if let string = value as? String, string == StitchStore.CloudRecordNilValue
         {
            managedObjectsDictionary[key] = StitchStore.CloudRecordNilValue as AnyObject?
            continue
         }
         //Some of these should maybe be thrown errors
         guard let relatnionship = entity.relationshipsByName[key] else { continue }
         guard let destinationName = relatnionship.destinationEntity?.name else { continue }
         guard let value = value as? CKRecord.Reference else { continue }

         let recordIDString = value.recordID.recordName
         let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: destinationName)
         fetchRequest.predicate = NSPredicate(backingReferenceID: recordIDString)
         fetchRequest.fetchLimit = 1
         guard let result = try context.fetch(fetchRequest).last else { throw StitchStore.StitchStoreError.invalidReferenceObject }
         managedObjectsDictionary[key] = result
      }
      return managedObjectsDictionary
   }

}
