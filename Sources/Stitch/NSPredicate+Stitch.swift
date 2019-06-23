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
   func expressionByReplacingManagedObjects(using store: StitchStore) throws -> NSExpression {
      guard expressionType == .constantValue,
         let value = constantValue as? NSManagedObject else { return self }

      try value.managedObjectContext?.obtainPermanentIDs(for: [value])
      guard let reference = store.referenceObject(for: value.objectID) as? String,
         let backing = store.backingObject(for: reference, entity: value.entity.name!) else { return self }

      return NSExpression(forConstantValue: backing)
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
