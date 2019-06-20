//
//  NSManagedObjectModel+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import CoreData

let SMLocalStoreEntityNameAttributeName = "sm_LocalStore_EntityName"
let SMLocalStoreChangeTypeAttributeName="sm_LocalStore_ChangeType"
let SMLocalStoreRecordIDAttributeName="sm_LocalStore_RecordID"
let SMLocalStoreRecordEncodedValuesAttributeName = "sm_LocalStore_EncodedValues"
let SMLocalStoreRecordChangedPropertiesAttributeName = "sm_LocalStore_ChangedProperties"
let SMLocalStoreChangeQueuedAttributeName = "sm_LocalStore_Queued"

let SMLocalStoreChangeSetEntityName = "SM_LocalStore_ChangeSetEntity"

extension NSEntityDescription {
   func modifyForStitchBackingStore() {
      managedObjectClassName = "NSManagedObject"
      let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
      recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
      recordIDAttribute.isOptional = false
      recordIDAttribute.isIndexed = true
      recordIDAttribute.attributeType = NSAttributeType.stringAttributeType
      properties.append(recordIDAttribute)
      let recordEncodedValuesAttribute: NSAttributeDescription = NSAttributeDescription()
      recordEncodedValuesAttribute.name = SMLocalStoreRecordEncodedValuesAttributeName
      recordEncodedValuesAttribute.attributeType = NSAttributeType.binaryDataAttributeType
      recordEncodedValuesAttribute.isOptional = true
      properties.append(recordEncodedValuesAttribute)
   }

   class func changeSetEntity() -> NSEntityDescription {
      let changeSetEntity: NSEntityDescription = NSEntityDescription()
      changeSetEntity.name = SMLocalStoreChangeSetEntityName

      let entityNameAttribute: NSAttributeDescription = NSAttributeDescription()
      entityNameAttribute.name = SMLocalStoreEntityNameAttributeName
      entityNameAttribute.attributeType = NSAttributeType.stringAttributeType
      entityNameAttribute.isOptional = true
      changeSetEntity.properties.append(entityNameAttribute)

      let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
      recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
      recordIDAttribute.attributeType = NSAttributeType.stringAttributeType
      recordIDAttribute.isOptional = false
      recordIDAttribute.isIndexed = true
      changeSetEntity.properties.append(recordIDAttribute)

      let recordChangedPropertiesAttribute: NSAttributeDescription = NSAttributeDescription()
      recordChangedPropertiesAttribute.name = SMLocalStoreRecordChangedPropertiesAttributeName
      recordChangedPropertiesAttribute.attributeType = NSAttributeType.stringAttributeType
      recordChangedPropertiesAttribute.isOptional = true
      changeSetEntity.properties.append(recordChangedPropertiesAttribute)

      let recordChangeTypeAttribute: NSAttributeDescription = NSAttributeDescription()
      recordChangeTypeAttribute.name = SMLocalStoreChangeTypeAttributeName
      recordChangeTypeAttribute.attributeType = NSAttributeType.integer16AttributeType
      recordChangeTypeAttribute.isOptional = false
      recordChangeTypeAttribute.defaultValue = NSNumber(value: StitchStore.RecordChange.inserted.rawValue as Int16)
      changeSetEntity.properties.append(recordChangeTypeAttribute)

      let changeTypeQueuedAttribute: NSAttributeDescription = NSAttributeDescription()
      changeTypeQueuedAttribute.name = SMLocalStoreChangeQueuedAttributeName
      changeTypeQueuedAttribute.isOptional = false
      changeTypeQueuedAttribute.attributeType = NSAttributeType.booleanAttributeType
      changeTypeQueuedAttribute.defaultValue = NSNumber(value: false as Bool)
      changeSetEntity.properties.append(changeTypeQueuedAttribute)
      return changeSetEntity
   }
}

extension NSManagedObjectModel {
   func stitchBackingModel() -> NSManagedObjectModel {
      let backingModel: NSManagedObjectModel = self.copy() as! NSManagedObjectModel
      for entity in backingModel.entities {
         entity.modifyForStitchBackingStore()
      }
      backingModel.entities.append(NSEntityDescription.changeSetEntity())
      return backingModel
   }
}
