//
//  NSManagedObjectModel+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import CoreData

extension NSEntityDescription {
   static let StitchStoreEntityNameAttributeName              = "sm_LocalStore_EntityName"
   static let StitchStoreChangeTypeAttributeName              = "sm_LocalStore_ChangeType"
   static let StitchStoreRecordChangedPropertiesAttributeName = "sm_LocalStore_ChangedProperties"
   static let StitchStoreChangeQueuedAttributeName            = "sm_LocalStore_Queued"
   static let StitchStoreChangeSetEntityName                  = "SM_LocalStore_ChangeSetEntity"

   static let StitchStoreRecordIDAttributeName                = "sm_LocalStore_RecordID"
   static let StitchStoreRecordEncodedValuesAttributeName     = "sm_LocalStore_EncodedValues"

   func modifyForStitchBackingStore() {
      managedObjectClassName = NSStringFromClass(NSManagedObject.self)
      let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
      recordIDAttribute.name = NSEntityDescription.StitchStoreRecordIDAttributeName
      recordIDAttribute.isOptional = false
      recordIDAttribute.isIndexed = true
      recordIDAttribute.attributeType = NSAttributeType.stringAttributeType
      properties.append(recordIDAttribute)

      let recordEncodedValuesAttribute: NSAttributeDescription = NSAttributeDescription()
      recordEncodedValuesAttribute.name = NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName
      recordEncodedValuesAttribute.attributeType = NSAttributeType.binaryDataAttributeType
      recordEncodedValuesAttribute.isOptional = true
      properties.append(recordEncodedValuesAttribute)
   }

   class func changeSetEntity() -> NSEntityDescription {
      let changeSetEntity: NSEntityDescription = NSEntityDescription()
      changeSetEntity.name = StitchStoreChangeSetEntityName

      let entityNameAttribute: NSAttributeDescription = NSAttributeDescription()
      entityNameAttribute.name = StitchStoreEntityNameAttributeName
      entityNameAttribute.attributeType = NSAttributeType.stringAttributeType
      entityNameAttribute.isOptional = true
      changeSetEntity.properties.append(entityNameAttribute)

      let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
      recordIDAttribute.name = StitchStoreRecordIDAttributeName
      recordIDAttribute.attributeType = NSAttributeType.stringAttributeType
      recordIDAttribute.isOptional = false
      recordIDAttribute.isIndexed = true
      changeSetEntity.properties.append(recordIDAttribute)

      let recordChangedPropertiesAttribute: NSAttributeDescription = NSAttributeDescription()
      recordChangedPropertiesAttribute.name = StitchStoreRecordChangedPropertiesAttributeName
      recordChangedPropertiesAttribute.attributeType = NSAttributeType.stringAttributeType
      recordChangedPropertiesAttribute.isOptional = true
      changeSetEntity.properties.append(recordChangedPropertiesAttribute)

      let recordChangeTypeAttribute: NSAttributeDescription = NSAttributeDescription()
      recordChangeTypeAttribute.name = StitchStoreChangeTypeAttributeName
      recordChangeTypeAttribute.attributeType = NSAttributeType.integer16AttributeType
      recordChangeTypeAttribute.isOptional = false
      recordChangeTypeAttribute.defaultValue = NSNumber(value: StitchStore.RecordChange.inserted.rawValue as Int16)
      changeSetEntity.properties.append(recordChangeTypeAttribute)

      let changeTypeQueuedAttribute: NSAttributeDescription = NSAttributeDescription()
      changeTypeQueuedAttribute.name = StitchStoreChangeQueuedAttributeName
      changeTypeQueuedAttribute.isOptional = false
      changeTypeQueuedAttribute.attributeType = NSAttributeType.booleanAttributeType
      changeTypeQueuedAttribute.defaultValue = NSNumber(value: false as Bool)
      changeSetEntity.properties.append(changeTypeQueuedAttribute)
      return changeSetEntity
   }
}

extension NSManagedObjectModel {
   func copyStitchBackingModel() -> NSManagedObjectModel {
      let backingModel: NSManagedObjectModel = self.copy() as! NSManagedObjectModel
      for entity in backingModel.entities {
         entity.modifyForStitchBackingStore()
      }
      backingModel.entities.append(NSEntityDescription.changeSetEntity())
      return backingModel
   }

   func validateStitchStoreModel(for configuration: String? = nil) -> Bool {
      var result = true
      if !configurations.contains(configuration ?? "Default") {
         print("model has no configuration named \(configuration ?? "Default")")
         result = false
      }
      for entity in entities(forConfigurationName: configuration ?? "Default") ?? [] {
         for (_, relationship) in entity.relationshipsByName {
            if let inverse = relationship.inverseRelationship {
               if relationship.isToMany && inverse.isToMany {
                  print("Many to many relationships are not presently supported.")
                  print("Invalid model for Stitch! \(relationship.name) to \(inverse.name)")
                  result = false
               }
            } else {
               print("relationship \(relationship.name) has no inverse! Invalid model for Stitch.")
               result = false
            }
         }
      }

      return result
   }

   func syncKeysExcludingAssetKeys(_ excludedAssetKeys: [String]) -> [String] {
      var keys = Set<String>()

      for entity in self.entities {
         for (name, property) in entity.propertiesByName {
            if name == NSEntityDescription.StitchStoreRecordIDAttributeName ||
               name == NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName
            {
               continue
            }
            if excludedAssetKeys.contains(name) {
               continue
            }
            if property.isTransient {
               continue
            }
            if let relationship = property as? NSRelationshipDescription, relationship.isToMany {
               continue
            }

            keys.insert(name)
         }
      }
      return Array(keys)
   }
}
