//
//  NSManagedObjectModel+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/19/19.
//

import CoreData

extension NSManagedObjectModel {
   func copyStitchBackingModel() -> NSManagedObjectModel {
      let backingModel: NSManagedObjectModel = self.copy() as! NSManagedObjectModel
      for entity in backingModel.entities {
         entity.modifyForStitchBackingStore()
      }
      let changeSetEntity = NSEntityDescription.changeSetEntity()
      backingModel.entities.append(changeSetEntity)
      // TODO: Add test for this
      for configuration in backingModel.configurations {
         let configEntities = backingModel.entities(forConfigurationName: configuration) ?? []
         backingModel.setEntities(configEntities + [changeSetEntity],
                                  forConfigurationName: configuration)
      }
      return backingModel
   }

   func validateStitchStoreModel(for configuration: String = "Default") -> Bool {
      var result = true
      if !configurations.contains(configuration) {
         print("model has no configuration named \(configuration)")
         result = false
      }
      for entity in entities(forConfigurationName: configuration) ?? [] {
         // Add tests for this!
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
