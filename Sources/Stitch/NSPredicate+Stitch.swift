//
//  NSPredicate+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

extension NSPredicate {
   @objc func predicateByReplacingManagedObjects(using store: StitchStore) throws -> NSPredicate {
//      print("predicate format: \(predicateFormat)")
      return self
   }

   convenience init(backingReferenceID: String) {
      self.init(format: "%K == %@", StitchStore.BackingModelNames.RecordIDAttribute, backingReferenceID)
   }
}

extension NSExpression {
   func backingObject(for outward: NSManagedObject, using store: StitchStore) throws -> NSManagedObject {
      try outward.managedObjectContext?.obtainPermanentIDs(for: [outward])
      guard let reference = store.referenceObject(for: outward.objectID) as? String else { throw StitchStore.StitchStoreError.invalidReferenceObject }
      guard let backing = store.backingObject(for: reference, entity: outward.entityName) else { throw StitchStore.StitchStoreError.invalidReferenceObject }
      return backing
   }

   func expressionByReplacingManagedObjects(using store: StitchStore) throws -> NSExpression {
      guard expressionType == .constantValue else { return self }
      if let value = constantValue as? NSManagedObject {
         let backing = try backingObject(for: value, using: store)
         return NSExpression(forConstantValue: backing)
      } else if let value = constantValue as? [NSManagedObject] {
         let mapped = try value.map { try backingObject(for: $0, using: store) }
         return NSExpression(forConstantValue: mapped)
      } else if let value = constantValue as? Set<NSManagedObject> {
         let mapped = try value.map { try backingObject(for: $0, using: store) }
         return NSExpression(forConstantValue: mapped)
      }
      return self
   }
}

extension NSComparisonPredicate {
   override func predicateByReplacingManagedObjects(using store: StitchStore) throws -> NSPredicate {
      let rightExp = try rightExpression.expressionByReplacingManagedObjects(using: store)
      let leftExp = try leftExpression.expressionByReplacingManagedObjects(using: store)
      
      return NSComparisonPredicate(leftExpression: leftExp,
                                   rightExpression: rightExp,
                                   modifier: comparisonPredicateModifier,
                                   type: predicateOperatorType,
                                   options: options)
   }
}

extension NSCompoundPredicate {
   override func predicateByReplacingManagedObjects(using store: StitchStore) throws -> NSPredicate {
      guard let subpredicates = subpredicates as? [NSPredicate] else { return self }
      var replacements = [NSPredicate]()
      for subpredicate in subpredicates {
         try replacements.append(subpredicate.predicateByReplacingManagedObjects(using: store))
      }
      return NSCompoundPredicate(type: compoundPredicateType, subpredicates: replacements)
   }
}
