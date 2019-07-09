# Stitch, a CoreData to CloudKit sync library
![](https://raw.githubusercontent.com/JCFalkenberg/Stitch/master/Assets/Stitch.png)

[![License](https://img.shields.io/github/license/jcfalkenberg/Stitch.svg)](/LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS-lightgrey.svg)](https://apple.com)
[![Language](https://img.shields.io/badge/language-Swift-orange.svg)](https://swift.org)
![GitHub tag (latest SemVer)](https://img.shields.io/github/tag/jcfalkenberg/Stitch.svg?label=version)

| Platform | Tests | Coverage |
|----|----|----|
| macOS | ![Tests](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fdarkchocolatesoftware.com%2Fstitch%2FStitchTester%2520Bot-Tests.json) | ![Coverage](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fdarkchocolatesoftware.com%2Fstitch%2FStitchTester%2520Bot-Coverage.json) |
| iOS | ![Tests](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fdarkchocolatesoftware.com%2Fstitch%2FStitchTester-iOS%2520Bot-Tests.json) | ![Coverage](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fdarkchocolatesoftware.com%2Fstitch%2FStitchTester-iOS%2520Bot-Coverage.json) |
| tvOS | ![Tests](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fdarkchocolatesoftware.com%2Fstitch%2FStitchTester-tvOS%2520Bot-Tests.json) | ![Coverage](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fdarkchocolatesoftware.com%2Fstitch%2FStitchTester-tvOS%2520Bot-Coverage.json) |
| watchOS | build info only - soon |  |

### Stitch is a framework built to sync a CoreData store to CloudKit, with backwards compatibility to older OS's than CloudKit+CoreData.

## This is a work in progress alpha. It builds, it has some tests for the non syncing portions of the code.

## Warnings
Stitch like it's namesake has some prickly parts to be aware of right off the bat. 
* It doesn't suport public CloudKit databases.
* It doesn't support CloudKit shared private databases.
* It doesn't support direct many to many relationships, but you can work around this by building a linking table entity.
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
* It does support as best it can, a lot of NSSQLiteStore features, as the default local backing store is an NSSQLiteStore
* It does allow for other backing store types, although some may have some issues vs NSSQLiteStore
* Syncing can happen automatically on save
* Store sets up CloudKit database zone, and subscription automatically
* Customizable CloudKit database identifier, zone and subscription names
* Cross Apple device, it supports macOS, iOS and tvOS, and watchOS

## CoreData to CloudKit

### Attributes

| CoreData  | CloudKit |
| ------------- | ------------- |
| Date | Date/Time |
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
| To - one | To one relationships are translated as CKReferences in the CloudKit Container. |
| To - many | To many relationships are not explicitly created, Stitch only creates and manages to-one relationships in CloudKit and then translates those back when syncing down.<br/><strong>Example</strong> -> If an Employee has a to-one relationship to Department and Department has a to-many relationship to Employee than Stitch will only link the employee to the department in CloudKit. During sync, it translates these back in the local store |
| many - many | Stitch does not support these directly. You can create them though using a [linking table](https://en.wikipedia.org/wiki/Associative_entity) |

<strong>Note :</strong> You must create inverse relationships in your app's CoreData Model or Stitch won't be able to translate CoreData Models in to CloudKit Records. Unexpected errors and curroption of data can possibly occur.

## Sync

Stitch keeps the CoreData store in sync with the CloudKit Servers.

After a sync completes, you must integrate the changes in to your UI. More on this to come.

#### Conflict Resolution Policies
In case of any sync conflicts, Stitch exposes 2 conflict resolution policies. Defined in `StitchStore.ConflictPolicy`

- `serverWins` - This is the default. It considers the server record as the true record.
- `clientWins` - This considers the client record as the true record.

## How to use

- Add a store type of `StitchStore.storeType` to your app's NSPersistentStoreCoordinator and assign it to the property created in the previous step.
- Pass in an appropriate options dictionary,
```swift
do {
   let store  = try coordinator.addPersistentStoreWithType(StitchStore.storeType,
                                                           configuration: nil,
                                                           URL: url,
                                                           options: options) as? StitchStore
   store?.triggerSync(.storeAdded)
} catch {
   print("There was an error adding the store! \(error)")
}
```
- Enable Push Notifications for your app.
- Register for push notifications somewhere, such as applicationDidFinishLaunching
- iOS:
```swift
UIApplication.shared.registerForRemoteNotifications()
```
- macOS:
```swift
NSApp.registerForRemoteNotifications(matching: .alert)
```

- Implement didReceiveRemoteNotification Method in your AppDelegate and call `handlePush` on the instance of SMStore created earlier.
```swift
func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) 
{
   self.smStore?.handlePush(userInfo: userInfo)
}
```
- Enjoy

## Options 

Defined in `StitchStore.Options`

* `FetchRequestPredicateReplacement` NSNumber boolean that enables replacement of NSManagedObjects in NSPredicates on NSFetchRequests.
defaults to false
FetchRequest preidcate replacement option. Requires objects to be replaced be saved prior to replacing them, otherwise errors will be thrown.
Supports replacing managed objects in: "keyPath == %@", "keyPath in %@" and "%@ contains %@" predicates, as well as compound predicates with those as sub predicates.

* `SyncConflictResolutionPolicy` is an NSNumber of the raw value of one of the options in StitchStore.ConflictPolicy.
Defaults to `StitchStore.ConflictPolicy.serverWins`

* `CloudKitContainerIdentifier` is a String identifying which CloudKit container ID to use if your app uses an identifier which does not match your Bundle ID.
Defaults to using `CKContainer.default().privateCloudDatabase`

* `ConnectionStatusDelegate` an object which conforms to StitchConnectionStatus for asking whether we have an internet connection at the moment

* `ExcludedUnchangingAsyncAssetKeys` is an array of Strings which indicate keys which should not be synced down during the main cycle due to being a large CKAsset
Syncing down can be done later on request or demand based on application need
Your asset containing properties should not overlap in name with other keys you want synced down to use this
Defaults to `nil`

* `BackingStoreType` is a string which defines what type of backing store is to be used. Defaults to NSSQLiteStoreType and testing is done against this type. Other stores may have issues.

* `SyncOnSave` an NSNumber boolean value for whether to automatically sync when the database is told to save.
Defaults to `true`.

* `ZoneNameOption` Lets you specify a string to use as the CloudKitZone ID name
Defaults to `StitchStore.SubscriptionInfo.CustomZoneName`

* `SubscriptionNameOption` Lets you specify a string to use as the CloudKit subscription name ID
Defaults to `StitchStore.SubscriptionInfo.SubscriptioName`

## Requirements

Xcode 11

Swift 5.1

## Support

## Getting Started 


## Installation
Simply add the git url to Swift Package Manager in Xcode 11

## Credits
Stitch was created by [Elizabeth Siemer](https://twitter.com/_woebetide_), based on a heavily modified by me fork of [Seam](https://github.com/nofelmahmood/Seam) by [Nofel Mahmood](https://twitter.com/NofelMahmood) but it has been nearly completely rewritten.

## Contact 
Follow Elizabeth on [Twitter](http://twitter.com/_woebetide) and [GitHub](http://github.com/nofelmahmood) or email her at elizabeth@darkchocolatesoftware.com

## License
Stitch is available under the MIT license. See the LICENSE file for more info.
