//
//  NSEntityDescription+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

extension NSAttributeDescription {
   convenience init(_ name: String,
                    optional: Bool,
                    indexed: Bool = false,
                    defaultValue: Any? = nil,
                    type: NSAttributeType)
   {
      self.init()
      self.name = name
      isOptional = optional
      isIndexed = indexed
      attributeType = type
      self.defaultValue = defaultValue
   }
}

extension NSEntityDescription {
   static let StitchStoreEntityNameAttributeName              = "sm_LocalStore_EntityName"
   static let StitchStoreChangeTypeAttributeName              = "sm_LocalStore_ChangeType"
   static let StitchStoreRecordChangedPropertiesAttributeName = "sm_LocalStore_ChangedProperties"
   static let StitchStoreChangeQueuedAttributeName            = "sm_LocalStore_Queued"
   static let StitchStoreChangeSetEntityName                  = "SM_LocalStore_ChangeSetEntity"

   static let StitchStoreRecordIDAttributeName                = "sm_LocalStore_RecordID"
   static let StitchStoreRecordEncodedValuesAttributeName     = "sm_LocalStore_EncodedValues"

   convenience init(_ name: String,
                    attributes: [NSAttributeDescription],
                    className: String = NSStringFromClass(NSManagedObject.self))
   {
      self.init()
      self.name = name
      self.properties.append(contentsOf: attributes)
      managedObjectClassName = className
   }

   func modifyForStitchBackingStore() {
      managedObjectClassName = NSStringFromClass(NSManagedObject.self)
      properties.append(NSAttributeDescription(NSEntityDescription.StitchStoreRecordIDAttributeName,
                                               optional: false,
                                               indexed: true,
                                               type: .stringAttributeType))

      properties.append(NSAttributeDescription(NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName,
                                               optional: true,
                                               type: .binaryDataAttributeType))
   }


   class func changeSetEntity() -> NSEntityDescription {
      let attributes = [
         NSAttributeDescription(StitchStoreEntityNameAttributeName,
                                optional: true,
                                type: .stringAttributeType),
         NSAttributeDescription(StitchStoreRecordIDAttributeName,
                                optional: false,
                                indexed: true,
                                type: .stringAttributeType),
         NSAttributeDescription(StitchStoreRecordChangedPropertiesAttributeName,
                                optional: true,
                                type: .stringAttributeType),
         NSAttributeDescription(StitchStoreChangeTypeAttributeName,
                                optional: false,
                                defaultValue: NSNumber(value: StitchStore.RecordChange.inserted.rawValue),
                                type: .integer16AttributeType),
         NSAttributeDescription(StitchStoreChangeQueuedAttributeName,
                                optional: false,
                                defaultValue: NSNumber(value: false),
                                type: .booleanAttributeType)
      ]

      return NSEntityDescription(StitchStoreChangeSetEntityName,
                                 attributes: attributes,
                                 className: NSStringFromClass(ChangeSet.self))
   }

   var attributesByNameSansBacking: [String: NSAttributeDescription] {
      return attributesByName.filter {
         $0.key != NSEntityDescription.StitchStoreRecordIDAttributeName &&
         $0.key != NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName
      }
   }

   var toOneRelationships: [NSRelationshipDescription] {
      return relationshipsByName.values.filter { $0.isToMany == false }
   }

   var toOneRelationshipsByName: [String:NSRelationshipDescription] {
      return relationshipsByName.filter { $0.value.isToMany == false }
   }
}
