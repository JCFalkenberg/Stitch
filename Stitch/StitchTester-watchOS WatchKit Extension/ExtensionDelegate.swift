//
//  ExtensionDelegate.swift
//  StitchTester-watchOS WatchKit Extension
//
//  Created by Elizabeth Siemer on 7/2/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import WatchKit
import CoreData
import Stitch

class ExtensionDelegate: NSObject, WKExtensionDelegate, StitchConnectionStatus {
   var internetConnectionAvailable: Bool { return true }

   var coordinator: NSPersistentStoreCoordinator? = nil
   var store: StitchStore? = nil
   var context: NSManagedObjectContext? = nil
   
   func applicationDidFinishLaunching() {
      // Perform any final initialization of your application.

      guard let url = Bundle.main.url(forResource: "TestModel", withExtension: "momd") else { return }
      guard let model = NSManagedObjectModel(contentsOf: url) else { return }
      guard var storeURL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask).first else { return }
      storeURL.appendPathComponent("StitchTests.store")
      coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
      do {
         store = try coordinator?.addPersistentStore(ofType: StitchStore.storeType,
                                                     configurationName: "Success",
                                                     at: storeURL,
                                                     options:
            [
               StitchStore.Options.ConnectionStatusDelegate: self,
               StitchStore.Options.FetchRequestPredicateReplacement: NSNumber(value: true),
               StitchStore.Options.CloudKitContainerIdentifier: "iCloud.com.darkchocolatesoftware.StitchTester",
               StitchStore.Options.ZoneNameOption: "WatchTestsZone"
            ]
         ) as? StitchStore
         context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
         context?.persistentStoreCoordinator = coordinator

         NotificationCenter.default.addObserver(self,
                                                selector: #selector(syncNotification(_:)),
                                                name: StitchStore.Notifications.DidFinishSync,
                                                object: store)
         NotificationCenter.default.addObserver(self,
                                                selector: #selector(syncNotification(_:)),
                                                name: StitchStore.Notifications.DidFailSync,
                                                object: store)
         NotificationCenter.default.addObserver(self,
                                                selector: #selector(syncNotification(_:)),
                                                name: StitchStore.Notifications.DidStartSync,
                                                object: store)
         store?.triggerSync(.storeAdded)
      } catch {
         print("error adding store \(error)")
      }
   }

   @objc func syncNotification(_ note: Notification) {
      if note.name == StitchStore.Notifications.DidFinishSync {
         print("sync succeeded")
      } else if note.name == StitchStore.Notifications.DidFailSync {
         print("Failed sync! \(String(describing: note.userInfo))")
      } else if note.name == StitchStore.Notifications.DidStartSync {
         print("started")
      } else {
         print("Unexpected sync note")
      }
   }
   
   func applicationDidBecomeActive() {
      // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
   }
   
   func applicationWillResignActive() {
      // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
      // Use this method to pause ongoing tasks, disable timers, etc.
   }
   
   func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
      // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
      for task in backgroundTasks {
         // Use a switch statement to check the task type
         switch task {
         case let backgroundTask as WKApplicationRefreshBackgroundTask:
            // Be sure to complete the background task once you’re done.
            backgroundTask.setTaskCompletedWithSnapshot(false)
         case let snapshotTask as WKSnapshotRefreshBackgroundTask:
            // Snapshot tasks have a unique completion call, make sure to set your expiration date
            snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
         case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
            // Be sure to complete the connectivity task once you’re done.
            connectivityTask.setTaskCompletedWithSnapshot(false)
         case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
            // Be sure to complete the URL session task once you’re done.
            urlSessionTask.setTaskCompletedWithSnapshot(false)
         case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
            // Be sure to complete the relevant-shortcut task once you're done.
            relevantShortcutTask.setTaskCompletedWithSnapshot(false)
         case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
            // Be sure to complete the intent-did-run task once you're done.
            intentDidRunTask.setTaskCompletedWithSnapshot(false)
         default:
            // make sure to complete unhandled task types
            task.setTaskCompletedWithSnapshot(false)
         }
      }
   }
   
}
