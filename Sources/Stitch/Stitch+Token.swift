//
//  Stitch+Token.swift
//  
//
//  Created by Elizabeth Siemer on 6/23/19.
//

import Foundation
import CloudKit

extension StitchStore {
   func token() -> CKServerChangeToken? {
      guard let data = metadata[Metadata.SyncTokenKey] as? Data else { return nil }
      return NSKeyedUnarchiver.unarchiveObject(with: data) as? CKServerChangeToken
   }

   func saveToken(_ serverChangeToken: CKServerChangeToken?) {
      newToken = serverChangeToken
   }

   func unCommittedToken() -> CKServerChangeToken? {
      return newToken
   }

   func commitToken() {
      if let token = self.newToken {
         let data = NSKeyedArchiver.archivedData(withRootObject: token)
         setMetadata(data as AnyObject, key: Metadata.SyncTokenKey)
      }
   }

   func deleteToken() {
      setMetadata(nil, key: Metadata.SyncTokenKey)
   }
}
