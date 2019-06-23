//
//  NSManagedObject+CKRecord.swift
//  
//
//  Created by Elizabeth Siemer on 6/22/19.
//

import CoreData
import CloudKit

extension NSManagedObject {
   subscript(key: String) -> Any? {
      get {
         return self.value(forKey: key)
      }
      set(newValue) {
         self.setValue(newValue, forKey: key)
      }
   }

   var entityName: String {
      return entity.name!
   }

   func ckRecordID(zone: CKRecordZone.ID) -> CKRecord.ID? {
      guard let recordIDString = self[StitchStore.BackingModelNames.RecordIDAttribute] as? String else { return nil }
      return CKRecord.ID(recordName: recordIDString, zoneID: zone)
   }

   func setAttributes(of record: CKRecord, with keys: [String]?)
   {
      let attributeKeys: [String] = keys != nil ? keys! : Array(entity.attributesByNameSansBacking.keys)

      for key in attributeKeys {
         guard let attribute = entity.attributesByName[key], !attribute.isTransient else { continue }
         guard let value = self[key] else {
            record.setValue(nil, forKey: key)
            continue
         }

         switch attribute.attributeType {
         case .stringAttributeType:
            record.setObject(value as? CKRecordValue ?? nil, forKey: key)
         case .dateAttributeType:
            record.setObject(value as? CKRecordValue ?? nil, forKey: key)
         case .binaryDataAttributeType:
            if attribute.allowsExternalBinaryDataStorage {
               if let data = value as? Data {
                  var tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                  tempURL = tempURL.appendingPathComponent("CKAssetTemp")
                  do
                  {
                     try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
                     tempURL = tempURL.appendingPathComponent(UUID().uuidString)
                     try data.write(to: tempURL, options: [.atomic])
                     let asset = CKAsset(fileURL: tempURL)
                     record.setObject(asset, forKey: key)
                  } catch {
                     print("Error saving file \(error)")
                  }
               } else {
                  record.setObject(nil, forKey: key)
               }
            } else {
               record.setObject(value as? CKRecordValue ?? nil, forKey: key)
            }
         case .booleanAttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         case .decimalAttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         case .doubleAttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         case .floatAttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         case .integer16AttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         case .integer32AttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         case .integer64AttributeType:
            record.setObject(value as? NSNumber ?? nil, forKey: key)
         default:
            break
         }
      }
   }

   func setRelationships(of record: CKRecord, with keys: [String]?) {
      let relationshipKeys: [String] = keys != nil ? keys! : Array(entity.toOneRelationshipsByName.keys)

      for key in relationshipKeys {
         guard let relatedObject = self[key] as? NSManagedObject,
            let recordID = relatedObject.ckRecordID(zone: record.recordID.zoneID) else {
            record.setObject(nil, forKey: key)
            continue
         }
         let reference = CKRecord.Reference(recordID: recordID, action: .deleteSelf)
         record.setObject(reference, forKey: key)
      }
   }

   func updatedCKRecord(zone: CKRecordZone.ID, using changedKeys: [String]? = nil) -> CKRecord? {
      let encoded: Data? = self[StitchStore.BackingModelNames.RecordEncodedAttribute] as? Data
      var record: CKRecord? = nil
      if let encoded = encoded {
         record = CKRecord(with: encoded)
      }
      if record == nil {
         if let recordID = ckRecordID(zone: zone) {
            record = CKRecord(recordType: self.entity.name!, recordID: recordID)
         }
      }
      guard let ckRecord = record else { return nil }
      var attributeKeys: [String]? = nil
      var relationshipKeys: [String]? = nil
      if let keys = changedKeys {
         attributeKeys = self.entity.attributesByName.compactMap {
            return keys.contains($0.key) ? $0.key : nil
         }
         relationshipKeys = self.entity.toOneRelationshipsByName.compactMap {
            return keys.contains($0.key) ? $0.key : nil
         }
      }
      setAttributes(of: ckRecord, with: attributeKeys)
      setRelationships(of: ckRecord, with: relationshipKeys)

      return ckRecord
   }
}
