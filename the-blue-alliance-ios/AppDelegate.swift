//
//  AppDelegate.swift
//  the-blue-alliance
//
//  Created by Zach Orr on 1/7/17.
//  Copyright © 2017 The Blue Alliance. All rights reserved.
//

import UIKit
import CoreData
import TBAKit
import Firebase
import UserNotifications

public enum StatusConstants {
    static let currentSeasonKey = "current_season"
    static let downEventsKey = "down_events"
    static let latestAppVersionKey = "latest_app_version"
    static let minAppVersionKey = "min_app_version"
    static let isDatafeedDownKey = "is_datafeed_down"
    static let maxSeasonKey = "max_season"
}

let kReactNativeBundleURL = "kReactNativeBundleURL"
var downloadedBundleURL: URL? {
    // TODO: Check if this is *the same* location, or a different location every time
    // If it's the same location, be sure we can overwrite
    // If it's a different location, make sure we delete old versions
    guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
        return nil
    }
    return documentDirectory.appendingPathComponent("bundle.jsbundle")
}

// Notifications
// TODO: Subscribe to these notifications elsewhere
let kFetchedTBAStatus = "kFetchedTBAStatus"

let kNoSelectionNavigationController = "NoSelectionNavigationController"

extension TBAStatus {

    public static func defaultStatus() -> TBAStatus {
        // Set to the last safe year we know about
        let currentYear = UInt(2018)
        // TODO: Move this JSON in to some file that get's generated when we build for release
        let defaultStatusJSON: [String: Any] = [
            "android": [
                "latest_app_version": -1,
                "min_app_version": -1
            ],
            "current_season": currentYear,
            "down_events": [],
            "ios": [
                "latest_app_version": -1,
                "min_app_version": -1
            ],
            "is_datafeed_down": false,
            "max_season": currentYear
        ]

        return TBAStatus(json: defaultStatusJSON)!
    }

}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "TBA")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            container.viewContext.automaticallyMergesChangesFromParent = true

            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // TODO: Remove this
        TBAKit.sharedKit.apiKey = "OHBBu0QbDiIJYKhAedTfkTxdrkXde1C21Sr90L1f1Pac4ahl4FJbNptNiXbCSCfH"
        
        if let splitViewController = self.window?.rootViewController as? UISplitViewController {
            splitViewController.preferredDisplayMode = .allVisible
            splitViewController.delegate = self
            
            let tabBarController = splitViewController.viewControllers[0] as! UITabBarController
            for vc in tabBarController.viewControllers! {
                guard let nav = vc as? UINavigationController else {
                    continue
                }

                guard let dataVC = nav.topViewController as? Persistable else {
                    continue
                }
                dataVC.persistentContainer = self.persistentContainer
            }
        }
        
        setupAppearance()
        
        FirebaseApp.configure()
        Messaging.messaging().delegate = self

        // Attempt to download our newest React Native bundle
        // TODO: This needs some kind of cache-control
        updateReactNativeBundle()
        
        UNUserNotificationCenter.current().delegate = self
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { (_, _) in }
        application.registerForRemoteNotifications()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        fetchTBAStatus()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    // MARK: Private
    
    func setupAppearance() {
        let navigationBarAppearance = UINavigationBar.appearance()
        
        navigationBarAppearance.barTintColor = UIColor.primaryBlue
        navigationBarAppearance.tintColor = UIColor.white
        // Remove the shadow for a more seamless split between navigation bar and segmented controls
        navigationBarAppearance.shadowImage = UIImage()
        navigationBarAppearance.setBackgroundImage(UIImage(), for: .default)
        navigationBarAppearance.isTranslucent = false
        navigationBarAppearance.titleTextAttributes = [NSAttributedStringKey.foregroundColor: UIColor.white]
    }
    
}

// TBA-specific logic
extension AppDelegate {
    
    func updateReactNativeBundle() {
        var storageBucket = "zach-tba-dev.appspot.com"
        if let googleInfoPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let googleInfoDictionary = NSDictionary(contentsOfFile: googleInfoPath),
            let googleStorageBucket = googleInfoDictionary["STORAGE_BUCKET"] as? String {
            storageBucket = googleStorageBucket
        }
        
        let storage = Storage.storage()
        let jsBundleReference = storage.reference(forURL: String(format: "gs://%@/react-native/main.jsbundle", storageBucket))
        
        // Store URL for online bundle - fetch online bundle when possible
        jsBundleReference.downloadURL { (url, error) in
            if let error = error {
                print("Unable to fetch download URL for React Native bundle: \(error.localizedDescription)")
            } else if let url = url {
                // TODO: Store URL out somewhere....
                print("Got URL for React Native bundle: \(url)")
            }
        }
        
        // Download to the local filesystem
        guard let downloadedBundleURL = downloadedBundleURL else {
            return
        }

        jsBundleReference.write(toFile: downloadedBundleURL) { (url, error) in
            if let error = error {
                print("Error writing React Native bundle to filesystem: \(error.localizedDescription)")
            } else if let url = url {
                UserDefaults.standard.set(url, forKey: kReactNativeBundleURL)
                UserDefaults.standard.synchronize()
                print("Successfully download React Native bundle to: \(url.absoluteString)")
            }
        }
    }
    
    func fetchTBAStatus() {
        // Call our staus endpoint and save everything in NSUserDefaults
        _ = TBAKit.sharedKit.fetchStatus({ (status, error) in
            if let status = status {
                // Got a valid status back from the API - update everything
                UserDefaults.standard.set(status.currentSeason, forKey: StatusConstants.currentSeasonKey)
                UserDefaults.standard.set(status.downEvents, forKey: StatusConstants.downEventsKey)
                // Note: We can update these two keys as we ship future versions, along with some migration code
                UserDefaults.standard.set(status.ios.latestAppVersion, forKey: StatusConstants.latestAppVersionKey)
                UserDefaults.standard.set(status.ios.minAppVersion, forKey: StatusConstants.minAppVersionKey)
                UserDefaults.standard.set(status.datafeedDown, forKey: StatusConstants.isDatafeedDownKey)
                UserDefaults.standard.set(status.maxSeason, forKey: StatusConstants.maxSeasonKey)
                
                NotificationCenter.default.post(name: Notification.Name(kFetchedTBAStatus), object: status)
            } else {
                let defaultStatus = TBAStatus.defaultStatus()
                // Didn't get a valid response from API - grab our default status
                // Make sure we don't overwite too many things if they've already been set
                
                // Only set our current season if we haven't set our current season
                if UserDefaults.standard.integer(forKey: StatusConstants.currentSeasonKey) == 0 {
                    UserDefaults.standard.set(defaultStatus.currentSeason, forKey: StatusConstants.currentSeasonKey)
                }
                
                // Set our latest app version if we've never set our latest app version before *or* our latest app
                // version is less than the default latest app version
                let latestAppVersion = UserDefaults.standard.integer(forKey: StatusConstants.latestAppVersionKey)
                if latestAppVersion == 0 || latestAppVersion < defaultStatus.ios.latestAppVersion {
                    UserDefaults.standard.set(defaultStatus.ios.latestAppVersion, forKey: StatusConstants.latestAppVersionKey)
                }
                
                let minAppVersion = UserDefaults.standard.integer(forKey: StatusConstants.minAppVersionKey)
                if minAppVersion == 0 || minAppVersion < defaultStatus.ios.minAppVersion {
                    UserDefaults.standard.set(defaultStatus.ios.minAppVersion, forKey: StatusConstants.minAppVersionKey)
                }
                
                // Only set our max season if we haven't set our max season
                if UserDefaults.standard.integer(forKey: StatusConstants.maxSeasonKey) == 0 {
                    UserDefaults.standard.set(defaultStatus.maxSeason, forKey: StatusConstants.maxSeasonKey)
                }
                
                NotificationCenter.default.post(name: Notification.Name(kFetchedTBAStatus), object: defaultStatus)
            }
        })
    }

}

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        // Print full message.
        print("Will present")
        print(userInfo)
        
        // Handle notification information in foreground
        completionHandler([])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // Print full message.
        print("Push notification")
        print(userInfo)
        
        // Handle being launched from a push notification
        completionHandler()
    }
    
}

extension AppDelegate: MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        print("Firebase registration token: \(fcmToken)")
    }
    
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        print("Remote message")
        // TODO: I have *no* idea how these get hit
        print(remoteMessage.appData)
    }
    
}

extension AppDelegate: UISplitViewControllerDelegate {
    
    func splitViewController(_ splitViewController: UISplitViewController, showDetail vc: UIViewController, sender: Any?) -> Bool {
        // If our split view controller is collapsed and we're trying to show a detail view,
        // push it on the master navigation stack
        if splitViewController.isCollapsed,
            let masterTabBarController = splitViewController.viewControllers.first as? UITabBarController,
            // Need to get the VC for the currently selected tab...
            let masterNavigationController = masterTabBarController.selectedViewController as? UINavigationController {
            // We want to push the view controller, but make sure we're not pushing something in a nav controller
            guard let detailNavigationController = vc as? UINavigationController else {
                return false
            }
            
            guard let detailViewController = detailNavigationController.viewControllers.first else {
                return false
            }

            masterNavigationController.show(detailViewController, sender: nil)
            
            return true
        }
        
        return false
    }

    func primaryViewController(forCollapsing splitViewController: UISplitViewController) -> UIViewController? {
        // If collapsing and detail view controller is not a no selection navigation view controller,
        // push the first view controller on to primary navigation view controller and return
        // the primary tab bar controller
        if let detailNavigationController = splitViewController.viewControllers.last as? UINavigationController,
            detailNavigationController.restorationIdentifier != kNoSelectionNavigationController {
            // This is a view controller we want to push
            if let masterTabBarController = splitViewController.viewControllers.first as? UITabBarController,
                let masterNavigationController = masterTabBarController.selectedViewController as? UINavigationController {
                // Add the detail navigation controller stack to our root navigation controller
                masterNavigationController.viewControllers += detailNavigationController.viewControllers
                return masterTabBarController
            }
        }
        
        return splitViewController.viewControllers.first
    }
    
    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        // If our primary view controller is not a no selection view controller, pop the old one, return the tab bar,
        // and setup the detail view controller to be the primary view controller
        //
        // Otherwise, return our detail
        if let masterTabViewController = splitViewController.viewControllers.first as? UITabBarController,
            let masterNavigationController = masterTabViewController.selectedViewController as? UINavigationController,
            masterNavigationController.topViewController?.restorationIdentifier != kNoSelectionNavigationController {
            // We want to seperate this event view controller in to the detail view controller
            if let detailViewControllers = masterNavigationController.popToRootViewController(animated: true) {
                let detailNavigationController = UINavigationController()
                detailNavigationController.viewControllers = detailViewControllers
                splitViewController.viewControllers = [masterTabViewController, detailNavigationController]
                
                return detailNavigationController
            }
        }
        
        return emptyDetailViewController()
    }

    public func emptyDetailViewController() -> UIViewController {
        return UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: kNoSelectionNavigationController)
    }

}
