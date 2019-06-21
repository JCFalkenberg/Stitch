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

   func backingProperties(for outwardProperties: [NSPropertyDescription],
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
