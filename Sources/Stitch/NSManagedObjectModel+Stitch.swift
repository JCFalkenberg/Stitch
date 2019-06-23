//
//  NSManagedObjectModel+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import CoreData

extension NSManagedObjectModel {
   func copyStichBackingModel(for configuration: String) -> NSManagedObjectModel {
      let backingModel = self.copy() as! NSManagedObjectModel
      for entity in backingModel.entities(forConfigurationName: configuration) ?? [] {
         entity.modifyForStitchBackingStore()
      }
      let changeSetEntity = NSEntityDescription.changeSetEntity()
      backingModel.entities.append(changeSetEntity)
      // TODO: Add test for this
      backingModel.setEntities((backingModel.entities(forConfigurationName: configuration) ?? []) + [changeSetEntity],
                               forConfigurationName: configuration)
      return backingModel
   }

   func validateStitchStoreModel(for configuration: String) -> Bool {
      var result = true
      if !configurations.contains(configuration) {
         print("model has no configuration named \(configuration)")
         result = false
      }
      for entity in entities(forConfigurationName: configuration) ?? [] {
         if entity.name == NSEntityDescription.StitchStoreChangeSetEntityName {
            print("\(NSEntityDescription.StitchStoreChangeSetEntityName) is a reserved entity name")
            result = false
         }
         // Add tests for this!
         for attributeName in entity.attributesByName.keys {
            if attributeName == NSEntityDescription.StitchStoreRecordIDAttributeName ||
               attributeName == NSEntityDescription.StitchStoreRecordEncodedValuesAttributeName
            {
               print("\(attributeName) is a reserved attribute key")
               result = false
            }
         }
         for relationship in entity.relationshipsByName.values {
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

   func backingProperties(for outwardProperties: [Any],
                                      on entity: NSEntityDescription) -> [NSPropertyDescription]
   {
      var results: [NSPropertyDescription] = []
      for object in outwardProperties {
         if let propertyName = object as? String,
            let backingProperty = entity.propertiesByName[propertyName]
         {
            results.append(backingProperty)
         }
         if let property = object as? NSPropertyDescription,
            let backingProperty = entity.propertiesByName[property.name]
         {
            results.append(backingProperty)
         }
      }
      return results
   }
}
