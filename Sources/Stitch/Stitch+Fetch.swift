//
//  Stitch+Fetch.swift
//  
//
//  Created by Elizabeth Siemer on 6/22/19.
//

import CoreData

extension StitchStore
{
   internal func fetch(_ fetchRequest: NSFetchRequest<NSFetchRequestResult>,
                          context: NSManagedObjectContext) throws -> [Any]?
   {
      let request = try fetchRequest.transfer(to: self)

      var mappedResults = [AnyObject]()
      var caughtError: Error? = nil
      self.backingMOC.performAndWait {
         do {
            let resultsFromLocalStore = try self.backingMOC.fetch(request)
            if resultsFromLocalStore.count > 0 {
               for object in resultsFromLocalStore {
                  if let object = object as? NSManagedObject {
                     mappedResults.append(object.objectID)
                  } else if let objectID = object as? NSManagedObjectID {
                     mappedResults.append(objectID)
                  } else if let dictionary = object as? NSDictionary {
                     mappedResults.append(dictionary)
                  } else if let count = object as? NSNumber {
                     mappedResults.append(count)
                  }
               }
            }
         } catch {
            print("Error executing fetch request! \(error)")
            caughtError = error
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
      mappedResults = mappedResults.map{ (object: AnyObject) -> AnyObject in
         var result: AnyObject = object
         switch request.resultType {
         case .managedObjectResultType:
            if let object = object as? NSManagedObjectID {
               let outwardID = outwardManagedObjectID(object)
               result = context.object(with: outwardID)
            }
         case .managedObjectIDResultType:
            if let object = object as? NSManagedObjectID {
               result = outwardManagedObjectID(object)
            }
         default:
            result = object
         }
         return result
      }
      return mappedResults
   }

   static let CloudRecordNilValue = "@!SM_CloudStore_Record_Nil_Value"

   override public func newValuesForObject(with objectID: NSManagedObjectID,
                                           with context: NSManagedObjectContext) throws -> NSIncrementalStoreNode
   {
      guard let recordID = referenceObject(for: objectID) as? String else { throw StitchStoreError.invalidReferenceObject }

      let propertiesToFetch: [String] = objectID.entity.properties.compactMap {
         var result = false
         if let relationship = $0 as? NSRelationshipDescription {
            result = !relationship.isToMany
         }
         if let attribute = $0 as? NSAttributeDescription {
            if attribute.name == BackingModelNames.RecordIDAttribute ||
               attribute.name == BackingModelNames.RecordEncodedAttribute
            {
               result = true
            } else {
               result = !attribute.isTransient
            }
         }
         return result ? $0.name : nil
      }

      let request = NSFetchRequest<NSDictionary>(entityName: objectID.entity.name!)
      request.fetchLimit = 1
      request.predicate = NSPredicate(backingReferenceID: recordID)
      request.resultType = .dictionaryResultType
      request.propertiesToFetch = propertiesToFetch
      var result: NSDictionary? = nil
      var caughtError: Error? = nil
      self.backingMOC.performAndWait {
         do {
            result = try backingMOC.fetch(request).last
         } catch {
            caughtError = error
            print("error fetching dictionary results for new values \(error)")
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
      guard var backingDict = result as? Dictionary<String, NSObject> else { throw StitchStoreError.backingStoreFetchRequestError }
      for (key,value) in backingDict {
         if let string = value as? String, string == StitchStore.CloudRecordNilValue {
            backingDict[key] = nil
         }
         if let managedObjectID = value as? NSManagedObjectID {
            backingDict[key] = outwardManagedObjectID(managedObjectID)
         }
      }
      for relationship in objectID.entity.toOneRelationships {
         if backingDict[relationship.name] == nil {
            backingDict[relationship.name] = NSNull()
         }
      }
      return NSIncrementalStoreNode(objectID: objectID, withValues: backingDict, version: 1)
   }
   override public func newValue(forRelationship relationship: NSRelationshipDescription,
                                 forObjectWith objectID: NSManagedObjectID,
                                 with context: NSManagedObjectContext?) throws -> Any
   {
      guard let recordID = referenceObject(for: objectID) as? String else { throw StitchStoreError.invalidReferenceObject }

      let request = NSFetchRequest<NSManagedObject>(entityName: objectID.entity.name!)
      request.predicate = NSPredicate(backingReferenceID: recordID)
      request.fetchLimit = 1
      var object: NSManagedObject? = nil
      var caughtError: Error? = nil
      backingMOC.performAndWait {
         do {
            object = try self.backingMOC.fetch(request).last
         } catch {
            caughtError = error
            print("error retrieving object in new value for relationship \(error)")
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
      guard let backingObject = object else {
         throw StitchStoreError.backingStoreFetchRequestError
      }

      if relationship.isToMany {
         guard let relatedValues: Set<NSManagedObject> = backingObject[relationship.name] as? Set<NSManagedObject> else {
            throw StitchStoreError.backingStoreFetchRequestError
         }
         return Array(relatedValues.map { outwardManagedObjectID($0.objectID) }) as AnyObject
      } else {
         if let objectID = (backingObject[relationship.name] as? NSManagedObject)?.objectID {
            return outwardManagedObjectID(objectID)
         } else {
            return NSNull()
         }
      }
   }
}
