//
//  AppDelegate.swift
//  Sileo
//
//  Created by CoolStar on 8/29/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import UserNotifications
import Evander

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@main
class SileoAppDelegate: UIResponder, UIApplicationDelegate {
    public var window: UIWindow?
    private var didConfigureInterface = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        prepareProcessLaunch()
        // 无 scene 的旧路径仍可能带 window；有 scene 时 window 在 SceneDelegate 里再挂上。
        if window != nil {
            configureInterfaceIfNeeded()
        }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func attachMainWindow(_ window: UIWindow) {
        self.window = window
        configureInterfaceIfNeeded()
    }

    private func prepareProcessLaunch() {
        EvanderNetworking.CACHE_FORCE = .cachesDirectory
        #if !TARGET_SANDBOX && !targetEnvironment(simulator)
        let prefix = CommandPath.prefix
        let old = EvanderNetworking._cacheDirectory
        if prefix != "" && !old.path.hasPrefix(prefix) && !old.path.contains("/Containers/") {
            EvanderNetworking._cacheDirectory = URL(fileURLWithPath: prefix + old.path)
            if old.dirExists {
                deleteFileAsRoot(old)
            }
            if let bundleID = Bundle.main.bundleIdentifier {
                let jbCacheDir = URL(fileURLWithPath: "\(prefix)/var/mobile/Library/Caches/\(bundleID)")
                try? FileManager.default.createDirectory(at: jbCacheDir, withIntermediateDirectories: true)
                URLCache.shared = URLCache(
                    memoryCapacity: 20 * 1024 * 1024,
                    diskCapacity: 100 * 1024 * 1024,
                    directory: jbCacheDir
                )
            }
        }
        #endif
        // Prepare the Evander manifest
        Evander.prepare()
        #if targetEnvironment(macCatalyst)
        _ = MacRootWrapper.shared
        #endif
        SileoThemeManager.shared.updateUserInterface()
        // Begin parsing sources files
        _ = RepoManager.shared
        // Init the local database
        _ = PackageListManager.shared
        _ = DatabaseManager.shared
        _ = DownloadManager.shared
        // Start the language helper for customised localizations
        _ = LanguageHelper.shared
    }

    private func configureInterfaceIfNeeded() {
        guard !didConfigureInterface else {
            return
        }
        guard let tabBarController = self.window?.rootViewController as? UITabBarController else {
            fatalError("Invalid Storyboard")
        }
        didConfigureInterface = true
        modernizeSourcesSplitIfNeeded(in: tabBarController)
        if #available(iOS 26.0, *) {
            // iOS 26 会为系统标签栏提供 Liquid Glass；不要再覆盖系统材质。
            tabBarController.tabBar.isTranslucent = true
            tabBarController.tabBar.backgroundImage = nil
            tabBarController.tabBar.shadowImage = nil
            tabBarController.tabBar.barTintColor = nil
        } else {
            tabBarController.tabBar._blurEnabled = true
            tabBarController.tabBar.tag = WHITE_BLUR_TAG
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
            let updatesPrompt = UserDefaults.standard.bool(forKey: "updatesPrompt")
            if !updatesPrompt {
                if UIApplication.shared.backgroundRefreshStatus == .denied {
                    DispatchQueue.main.async {
                        let title = String(localizationKey: "Background_App_Refresh")
                        let msg = String(localizationKey: "Background_App_Refresh_Message")
                        
                        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                        let okAction = UIAlertAction(title: String(localizationKey: "OK"), style: .cancel) { _ in
                            alert.dismiss(animated: true, completion: nil)
                        }
                        alert.addAction(okAction)
                        self.window?.rootViewController?.presentSileoAlert(alert)
                        
                        UserDefaults.standard.set(true, forKey: "updatesPrompt")
                    }
                }
            }
        }
        
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: "sileo.backgroundrefresh",
                                            using: nil) { [weak self] task in
                self?.handleRefreshTask(task as! BGAppRefreshTask)
            }
        } else {
            UIApplication.shared.setMinimumBackgroundFetchInterval(4 * 3600)
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {_, _ in
            
        }
        
        _ = NotificationCenter.default.addObserver(forName: SileoThemeManager.sileoChangedThemeNotification, object: nil, queue: nil) { _ in
            self.updateTintColor()
            if #unavailable(iOS 26.0) {
                // 旧系统靠拆装 window 子视图强迫 appearance 生效；iOS 26 的玻璃按钮会被这步钉死旧色。
                for window in UIApplication.shared.windows {
                    for view in window.subviews {
                        view.removeFromSuperview()
                        window.addSubview(view)
                    }
                }
            }
        }
        self.updateTintColor()
        
        // Force all view controllers to load now
        for (index, controller) in (tabBarController.viewControllers ?? []).enumerated() {
            _ = controller.view
            if let navController = controller as? UINavigationController {
                _ = navController.viewControllers[0].view
            }
            if index == 4 {
                controller.tabBarItem._setInternalTitle(String(localizationKey: "Search_Page"))
            }
        }
    }

    private func modernizeSourcesSplitIfNeeded(in tabBarController: UITabBarController) {
        guard #available(iOS 26.0, *),
              UIDevice.current.userInterfaceIdiom == .pad,
              var tabViewControllers = tabBarController.viewControllers,
              tabViewControllers.indices.contains(2),
              let legacySourcesSplit = tabViewControllers[2] as? SourcesSplitViewController,
              legacySourcesSplit.style == .unspecified,
              legacySourcesSplit.viewControllers.count >= 2 else {
            return
        }

        // storyboard 创建的是旧式 split，iPadOS 26 隐藏主栏后仍会残留旧 safe-area。
        // 仅在新系统上换成现代双栏容器，并继续复用原来的主栏和详情导航栈。
        let sourceViewControllers = legacySourcesSplit.viewControllers
        let modernSourcesSplit = SourcesSplitViewController(style: .doubleColumn)
        modernSourcesSplit.tabBarItem = legacySourcesSplit.tabBarItem
        modernSourcesSplit.title = legacySourcesSplit.title
        legacySourcesSplit.viewControllers = []
        modernSourcesSplit.setViewController(sourceViewControllers[0], for: .primary)
        modernSourcesSplit.setViewController(sourceViewControllers[1], for: .secondary)
        tabViewControllers[2] = modernSourcesSplit
        tabBarController.setViewControllers(tabViewControllers, animated: false)
    }
    
    private func backgroundRepoRefreshTask(_ completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            PackageListManager.shared.initWait()
            let currentUpdates = PackageListManager.shared.availableUpdates().filter({ $0.1?.wantInfo != .hold }).map({ $0.0 })
            let currentPackages = PackageListManager.shared.allPackagesArray
            if currentUpdates.isEmpty { return completion() }
            RepoManager.shared.update(force: false, forceReload: false, isBackground: true) { _, _ in
                let newUpdates = PackageListManager.shared.availableUpdates().filter({ $0.1?.wantInfo != .hold }).map({ $0.0 })
                let newPackages = PackageListManager.shared.allPackagesArray
                if newPackages.isEmpty { return completion() }
                
                let diffUpdates = newUpdates.filter { !currentUpdates.contains($0) }
                if diffUpdates.count > 3 {
                    let content = UNMutableNotificationContent()
                    content.title = String(localizationKey: "Updates Available")
                    content.body = String(format: String(localizationKey: "New updates for %d packages are available"), diffUpdates.count)
                    content.badge = newUpdates.count as NSNumber
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    
                    let request = UNNotificationRequest(identifier: "org.coolstar.sileo.updates", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                } else {
                    for package in diffUpdates {
                        let content = UNMutableNotificationContent()
                        content.title = String(localizationKey: "New Update")
                        content.body = String(format: String(localizationKey: "%@ by %@ has been updated to version %@ on %@"),
                                              package.name ?? "",
                                              package.author?.name ?? "",
                                              package.version,
                                              package.sourceRepo?.displayName ?? "")
                        content.badge = newUpdates.count as NSNumber
                        
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                        
                        let request = UNNotificationRequest(identifier: "org.coolstar.sileo.update-\(package.package)",
                                                            content: content,
                                                            trigger: trigger)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                    }
                }

                let diffPackages = newPackages.filter { !currentPackages.contains($0) }
                let wishlist = WishListManager.shared.wishlist
                for package in diffPackages {
                    if wishlist.contains(package.package) {
                        let content = UNMutableNotificationContent()
                        content.title = String(localizationKey: "New Update")
                        content.body = String(format: String(localizationKey: "%@ by %@ has been updated to version %@ on %@"),
                                              package.name ?? "",
                                              package.author?.name ?? "",
                                              package.version,
                                              package.sourceRepo?.displayName ?? "")
                        content.badge = newUpdates.count as NSNumber
                        
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                        
                        let request = UNNotificationRequest(identifier: "org.coolstar.sileo.update-\(package.package)",
                                                            content: content,
                                                            trigger: trigger)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                    }
                }
                completion()
            }
        }
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        backgroundRepoRefreshTask {
            completionHandler(.newData)
        }
    }
    
    func updateTintColor() {
        var tintColor = UIColor.tintColor
        if UIAccessibility.isInvertColorsEnabled {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            tintColor = UIColor(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 1 - alpha)
        }
        
        if #available(iOS 13, *) {
        } else {
            if UIColor.isDarkModeEnabled {
                UINavigationBar.appearance().barStyle = .blackTranslucent
                UITabBar.appearance().barStyle = .black
                UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).keyboardAppearance = .dark
            } else {
                UINavigationBar.appearance().barStyle = .default
                UITabBar.appearance().barStyle = .default
                UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).keyboardAppearance = .default
            }
        }
        
        UINavigationBar.appearance().tintColor = tintColor
        UIToolbar.appearance().tintColor = tintColor
        UISearchBar.appearance().tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            // 浮动标签栏内部也使用 UICollectionView，全局 appearance 会把它固定为创建时的主题色。
            UICollectionView.appearance().tintColor = nil
        } else {
            UICollectionView.appearance().tintColor = tintColor
        }
        UITableView.appearance().tintColor = tintColor
        DepictionBaseView.appearance().tintColor = tintColor
        self.window?.tintColor = tintColor

        if #available(iOS 26.0, *),
           let tabBarController = self.window?.rootViewController as? UITabBarController {
            // iOS 26 的系统标签栏不再经过旧的 appearance blur，直接刷新选中态颜色。
            tabBarController.view.tintColor = tintColor
            tabBarController.tabBar.tintColor = tintColor
            tabBarController.tabBar.unselectedItemTintColor = .label
            if let tabBarController = tabBarController as? TabBarController {
                tabBarController.updateSileoColors()
            }
        }

        if #available(iOS 26.0, *) {
            refreshPresentedBarButtonItems(from: self.window?.rootViewController, tintColor: tintColor)
        }
    }

    @available(iOS 26.0, *)
    private func refreshPresentedBarButtonItems(from viewController: UIViewController?, tintColor: UIColor) {
        guard let viewController else {
            return
        }
        SileoGlass.refreshBarButtonItems(in: viewController, tintColor: tintColor)
        viewController.children.forEach { refreshPresentedBarButtonItems(from: $0, tintColor: tintColor) }
        if let presented = viewController.presentedViewController {
            refreshPresentedBarButtonItems(from: presented, tintColor: tintColor)
        }
    }
    
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        DispatchQueue.global(qos: .default).async {
            PackageListManager.shared.initWait()
            DispatchQueue.main.async {
                if url.scheme == "file" {
                    if url.pathExtension == "deb" {
                        // The file is a deb. Open the package view controller to that file.
                        guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                              let featuredVc = tabBarController.viewControllers?[0] as? UINavigationController?,
                              let featuredView = featuredVc?.viewControllers[0] as? FeaturedViewController else {
                                  return
                              }
                        guard let package = PackageListManager.shared.package(url: url) else {
                            let alert = UIAlertController(title: "Bad Deb", message: "The provided deb file could not be read", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: .cancel))
                            featuredView.presentSileoAlert(alert)
                            return
                        }
                        featuredView.showPackage(package)
                        tabBarController.selectedIndex = 0
                    } else {
                        guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                              let sourcesNavNV = (tabBarController.viewControllers?[2] as? SileoNavigationController) ??
                                  (tabBarController.viewControllers?[2] as? UISplitViewController)?.viewControllers[0] as? SileoNavigationController,
                              let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController,
                              url.startAccessingSecurityScopedResource() else {
                                  return
                              }
                        sourcesVC.importRepos(fromURL: url)
                        url.stopAccessingSecurityScopedResource()
                    }
                } else {
                    // presentModally ignored; we always present modally for an external URL open.
                    var presentModally = false
                    if let viewController = URLManager.viewController(url: url, isExternalOpen: true, presentModally: &presentModally) {
                        if let alertController = viewController as? UIAlertController {
                            self.window?.rootViewController?.presentSileoAlert(alertController)
                        } else {
                            self.window?.rootViewController?.present(viewController, animated: true, completion: nil)
                        }
                    }
                }
            }
        }
        
        if url.host == "source" && url.scheme == "sileo" {
            guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                let targetVC = tabBarController.viewControllers?[2],
                let sourcesNavNV = (targetVC as? SileoNavigationController) ??
                    (targetVC as? UISplitViewController)?.viewControllers[0] as? SileoNavigationController,
                let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController else {
                return false
            }
            let newURL = url.absoluteURL
            tabBarController.closePopup(animated: true)
            tabBarController.selectedViewController = targetVC
            sourcesVC.presentAddSourceEntryField(url: newURL)
        }
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        handleOpenURL(url)
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        handleShortcutItem(shortcutItem, completionHandler: completionHandler)
    }

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let tabBarController = TabBarController.singleton,
              let controllers = tabBarController.viewControllers,
              let targetVC = controllers[2] as UIViewController?,
              let sourcesNVC = (targetVC as? SileoNavigationController) ??
                  (targetVC as? UISplitViewController)?.viewControllers[0] as? SileoNavigationController,
              let sourcesVC = sourcesNVC.viewControllers[0] as? SourcesViewController,
              let packageListNVC = controllers[3] as? SileoNavigationController,
              let packageListVC = packageListNVC.viewControllers[0] as? PackageListViewController
        else {
            completionHandler(false)
            return
        }
        
        if shortcutItem.type.hasSuffix(".UpgradeAll") {
            tabBarController.closePopup(animated: true)
            tabBarController.selectedViewController = packageListNVC
            
            let title = String(localizationKey: "Sileo")
            let msg = String(localizationKey: "Upgrade_All_Shortcut_Processing_Message")
            let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
            packageListVC.presentSileoAlert(alert)
            
            sourcesVC.refreshSources(forceUpdate: true, forceReload: true, isBackground: false, useRefreshControl: true, useErrorScreen: true, completion: { _, _ in
                PackageListManager.shared.upgradeAll(completion: {
                    if UserDefaults.standard.bool(forKey: "AutoConfirmUpgradeAllShortcut", fallback: false) {
                        let downloadMan = DownloadManager.shared
                        downloadMan.reloadData(recheckPackages: false)
                    }
                    
                    tabBarController.presentPopupController()
                    alert.dismiss(animated: true, completion: nil)
                })
            })
        } else if shortcutItem.type.hasSuffix(".Refresh") {
            tabBarController.closePopup(animated: true)
            tabBarController.selectedViewController = targetVC
            sourcesVC.refreshSources(forceUpdate: true, forceReload: true, isBackground: false, useRefreshControl: true, useErrorScreen: true, completion: nil)
        } else if shortcutItem.type.hasSuffix(".AddSource") {
            tabBarController.closePopup(animated: true)
            tabBarController.selectedViewController = targetVC
            sourcesVC.addSource(nil)
        } else if shortcutItem.type.hasSuffix(".Packages") {
            tabBarController.closePopup(animated: true)
            tabBarController.selectedViewController = packageListNVC
        }
        completionHandler(true)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        UIColor.isTransitionLockedForiOS13Bug = true
        
        if #available(iOS 13.0, *) {
            scheduleTasks()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        UIColor.isTransitionLockedForiOS13Bug = false
    }
    
    @available(iOS 13.0, *)
    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        func _return() {
            task.setTaskCompleted(success: true)
            scheduleRefreshTask()
        }
        backgroundRepoRefreshTask {
            return _return()
        }
    }
    
    @available(iOS 13.0, *)
    private func scheduleRefreshTask() {
        let fetchTask = BGAppRefreshTaskRequest(identifier: "sileo.backgroundrefresh")
        fetchTask.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(fetchTask)
        } catch {
            print("Unable to submit task: \(error.localizedDescription)")
        }
    }
    
    @available(iOS 13.0, *)
    private func scheduleTasks() {
        scheduleRefreshTask()
    }
}
