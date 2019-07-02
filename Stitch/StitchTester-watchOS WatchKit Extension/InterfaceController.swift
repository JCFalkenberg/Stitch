//
//  InterfaceController.swift
//  StitchTester-watchOS WatchKit Extension
//
//  Created by Elizabeth Siemer on 7/2/19.
//  Copyright © 2019 Dark Chocolate Software, LLC. All rights reserved.
//

import WatchKit
import Foundation


class InterfaceController: WKInterfaceController {
   
   override func awake(withContext context: Any?) {
      super.awake(withContext: context)
      
      // Configure interface objects here.
   }
   
   override func willActivate() {
      // This method is called when watch view controller is about to be visible to user
      super.willActivate()
   }
   
   override func didDeactivate() {
      // This method is called when watch view controller is no longer visible
      super.didDeactivate()
   }
   
}
