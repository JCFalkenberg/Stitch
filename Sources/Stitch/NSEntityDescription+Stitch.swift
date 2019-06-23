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
      properties.append(NSAttributeDescription(StitchStore.BackingModelNames.RecordIDAttribute,
                                               optional: false,
                                               indexed: true,
                                               type: .stringAttributeType))

      properties.append(NSAttributeDescription(StitchStore.BackingModelNames.RecordEncodedAttribute,
                                               optional: true,
                                               type: .binaryDataAttributeType))
   }


   class func changeSetEntity() -> NSEntityDescription {
      let attributes = [
         NSAttributeDescription(StitchStore.BackingModelNames.EntityNameAttribute,
                                optional: true,
                                type: .stringAttributeType),
         NSAttributeDescription(StitchStore.BackingModelNames.RecordIDAttribute,
                                optional: false,
                                indexed: true,
                                type: .stringAttributeType),
         NSAttributeDescription(StitchStore.BackingModelNames.ChangedPropertiesAttribute,
                                optional: true,
                                type: .stringAttributeType),
         NSAttributeDescription(StitchStore.BackingModelNames.ChangeTypeAttribute,
                                optional: false,
                                defaultValue: NSNumber(value: StitchStore.RecordChange.inserted.rawValue),
                                type: .integer16AttributeType),
         NSAttributeDescription(StitchStore.BackingModelNames.ChangeQueuedAttribute,
                                optional: false,
                                defaultValue: NSNumber(value: false),
                                type: .booleanAttributeType)
      ]

      return NSEntityDescription(StitchStore.BackingModelNames.ChangeSetEntity,
                                 attributes: attributes,
                                 className: NSStringFromClass(ChangeSet.self))
   }

   var attributesByNameSansBacking: [String: NSAttributeDescription] {
      return attributesByName.filter {
         $0.key != StitchStore.BackingModelNames.RecordIDAttribute &&
         $0.key != StitchStore.BackingModelNames.RecordEncodedAttribute
      }
   }

   var toOneRelationships: [NSRelationshipDescription] {
      return relationshipsByName.values.filter { $0.isToMany == false }
   }

   var toOneRelationshipsByName: [String:NSRelationshipDescription] {
      return relationshipsByName.filter { $0.value.isToMany == false }
   }
}
