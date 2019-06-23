//
//  NSPredicate+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

extension NSPredicate {
   @objc func predicateByReplacingManagedObjects(using store: StitchStore) -> NSPredicate {
      print("predicate format: \(predicateFormat)")
      return self
   }

   convenience init(backingReferenceID: String) {
      self.init(format: "%K == %@", StitchStore.BackingModelNames.RecordIDAttribute, backingReferenceID)
   }
}

extension NSComparisonPredicate {
   override func predicateByReplacingManagedObjects(using store: StitchStore) -> NSPredicate {
      var rightExp = rightExpression
      var changes = false
      if rightExp.expressionType == .constantValue,
         let right = rightExp.constantValue as? NSManagedObject
      {
         do {
            try right.managedObjectContext?.obtainPermanentIDs(for: [right])
         } catch {
            print("error retrieving permanent id's \(error)")
         }
         if let reference = store.referenceObject(for: right.objectID) as? String,
            let backing = store.backingObject(for: reference, entity: right.entity.name!)
         {
            changes = true
            rightExp = NSExpression(forConstantValue: backing)
         }
      }

      var leftExp = leftExpression
      if leftExp.expressionType == .constantValue,
         let left = leftExp.constantValue as? NSManagedObject
      {
         do {
            try left.managedObjectContext?.obtainPermanentIDs(for: [left])
         } catch {
            print("error retrieving permanent id's \(error)")
         }
         if let reference = store.referenceObject(for: left.objectID) as? String,
            let backing = store.backingObject(for: reference, entity: left.entity.name!)
         {
            changes = true
            leftExp = NSExpression(forConstantValue: backing)
         }
      }
      if changes {
         return NSComparisonPredicate(leftExpression: leftExp,
                                      rightExpression: rightExp,
                                      modifier: comparisonPredicateModifier,
                                      type: predicateOperatorType,
                                      options: options)
      } else {
         return self
      }
   }
}

extension NSCompoundPredicate {
   override func predicateByReplacingManagedObjects(using store: StitchStore) -> NSPredicate {
      if let subpredicates = subpredicates as? [NSPredicate] {
         var replacements = [NSPredicate]()
         for subpredicate in subpredicates {
            replacements.append(subpredicate.predicateByReplacingManagedObjects(using: store))
         }
         return NSCompoundPredicate(type: compoundPredicateType, subpredicates: replacements)
      }
      print("predicate format: \(predicateFormat)")
      return self
   }
}
