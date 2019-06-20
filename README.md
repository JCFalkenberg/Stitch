# Stitch, a CoreData to CloudKit sync library

### Stitch is a framework built to sync a CoreData store to CloudKit, with backwards compatibility to older OS's than CloudKit+CoreData.

## Warnings
Stitch like it's namesake has some prickly parts to be aware of right off the bat. 
* It doesn't suport public CloudKit databases.
* It doesn't support CloudKit shared private databases.
* It doesn't support direct many to many relationships, but you can work around this by building a linking table entity.
* It doesn't support batch oerations
* It doesn't support the store version system
* It doesn't support ordered relationships
* Migrations involving renaming or changing properties, entities, or relationships
* CloudKit containers created with Stitch won't be compatible with CloudKit+CoreData but will be backwards compatible with older OS's
* You must handle iCloud account observation externally to Stitch.
* When sync finishes, you must integrate those changes in to your UI.
* Conflict resolution has been simplified to either server or local record wins.

It was built primarily for my needs, and I haven't needed these, but I am not opposed to working in support for those that make sense

## What does it do then?

So after seeing that scary list of sharp points, what does Stitch have to offer?
* Complete local cache, the store is fully usable offline, and changes will be queued for the next time the user connects to a network with the app open.
* Assets/External Data can be downloaded separately from the text data, either on demand or just as a separate sync phase (for instance, you can implement a download all assets when on wifi)
* Stitch supports both adding new entities and new fields to the database. Keep in mind that older versions of your app won't see the new properties until the user updates. Keep this in mind when designing your database.
* It does support as best it can, *most* NSSQLiteStore features, as the default local backing store is an NSSQLiteStore
* It does allow for other backing store types, although some may have some issues vs NSSQLiteStore
* Syncing can happen automatically on save
* Store sets up CloudKit database zone, and subscription automatically
* Customizable CloudKit database identifier, zone and subscription names

## CoreData to CloudKit

### Attributes

| CoreData  | CloudKit |
| ------------- | ------------- |
| Date    | Date/Time |
| Data | Bytes | 
| External Stored Data | CKAsset |
| String  | String  |
| Int16 | Int(64) |
| Int32 | Int(64) |
| Int64 | Int(64) |
| Decimal | Double | 
| Float | Double |
| Boolean | Int(64) |
| NSManagedObject | Reference |

### Relationships

| CoreData Relationship  | Translation on CloudKit |
| ------------- | ------------- |
| To - one    | To one relationships are translated as CKReferences on the CloudKit Servers. |
| To - many    | To many relationships are not explicitly created. Stitch only creates and manages to-one relationships on the CloudKit Servers. <br/> <strong>Example</strong> -> If an Employee has a to-one relationship to Department and Department has a to-many relationship to Employee than Stitch will only create the former on the CloudKit Servers. It will fullfil the later by using the to-one relationship. If all employees of a department are accessed Stitch will fulfil it by fetching all the employees that belong to that particular department.|

<strong>Note :</strong> You must create inverse relationships in your app's CoreData Model or Stitch won't be able to translate CoreData Models in to CloudKit Records. Unexpected errors and curroption of data can possibly occur.

## Sync

Stitch keeps the CoreData store in sync with the CloudKit Servers.
After a sync completes, you must integrate the changes in to your UI.

#### Conflict Resolution Policies
In case of any sync conflicts, Stitch exposes 2 conflict resolution policies.

- ServerRecordWins

This is the default. It considers the server record as the true record.

- ClientRecordWins

This considers the client record as the true record.

## How to use

- Declare a SMStore type property in the class where your CoreData stack resides.
```swift
var smStore: StitchStore?
```
- Add a store type of `StitchStore.storeType` to your app's NSPersistentStoreCoordinator and assign it to the property created in the previous step.
```swift
do 
{
self.smStore = try coordinator.addPersistentStoreWithType(StitchStore.storeType, configuration: nil, URL: url, options: nil) as? StitchStore
}
```
- Enable Push Notifications for your app.

- Implement didReceiveRemoteNotification Method in your AppDelegate and call `handlePush` on the instance of SMStore created earlier.
```swift
func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) 
{
self.smStore?.handlePush(userInfo: userInfo)
}
```
- Enjoy

## Options 

- StitchStoreSyncConflictResolutionPolicy

Use StitchSyncConflictResolutionPolicy enum to use as a value for this option to specify the desired conflict resolution policy when adding StitchStoreType to your app's NSPersistentStoreCoordinator.
## Requirements

Xcode 11

Swift 5.0

## Support

## Getting Started 


## Installation
Simply add the git url to Swift Package Manager in Xcode 11 

## Credits
Stitch was created by [Elizabeth Siemer](https://twitter.com/_woebetide_), originally modified from [Seam](https://github.com/) by [Nofel Mahmood](https://twitter.com/NofelMahmood) but it has been nearly completely rewritten.

## Contact 
Follow Elizabeth on [Twitter](http://twitter.com/_woebetide) and [GitHub](http://github.com/nofelmahmood) or email her at elizabeth@darkchocolatesoftware.com

## License
Stitch is available under the MIT license. See the LICENSE file for more info.
