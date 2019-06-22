//
//  NSManagedObjectContext+Stitch.swift
//  
//
//  Created by Elizabeth Siemer on 6/21/19.
//

import CoreData

extension NSManagedObjectContext {
   func saveIfHasChanges() throws {
      if self.hasChanges {
         try self.save()
      }
   }

   func saveInBlockIfHasChanges() throws {
      var caughtError: Error? = nil
      self.performAndWait { () -> Void in
         do {
            try self.saveIfHasChanges()
         } catch {
            caughtError = error
            print("error saving in block if has changes \(error)")
         }
      }
      if let caughtError = caughtError {
         throw caughtError
      }
   }
}
