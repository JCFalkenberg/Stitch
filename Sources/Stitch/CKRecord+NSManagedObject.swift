//
//  CKRecord+NSManagedObject.swift
//  
//
//  Created by Elizabeth Siemer on 6/22/19.
//

import CloudKit

extension CKRecord {
   convenience init?(with encodedFields: Data) {
      let coder = NSKeyedUnarchiver(forReadingWith: encodedFields)
      self.init(coder: coder)
      coder.finishDecoding()
   }
}
