//
//  SceneDelegate.swift
//  Sileo
//
//  把窗口生命周期从 AppDelegate 迁到 UIScene，满足 iOS 27 SDK 的启动要求。
//  不开启多窗口：全程仍只有一扇窗。
//

import UIKit

@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        if window == nil {
            let createdWindow = UIWindow(windowScene: windowScene)
            createdWindow.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
            window = createdWindow
        }
        guard let window, let appDelegate = UIApplication.shared.delegate as? SileoAppDelegate else {
            return
        }
        // 首帧显示前完成标签栏、主题和子页面初始化，避免 UIKit 缓存半初始化的布局。
        appDelegate.attachMainWindow(window)
        window.makeKeyAndVisible()

        if let shortcutItem = connectionOptions.shortcutItem {
            appDelegate.handleShortcutItem(shortcutItem) { _ in }
        }
        for context in connectionOptions.urlContexts {
            appDelegate.handleOpenURL(context.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let appDelegate = UIApplication.shared.delegate as? SileoAppDelegate else {
            return
        }
        for context in URLContexts {
            appDelegate.handleOpenURL(context.url)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let appDelegate = UIApplication.shared.delegate as? SileoAppDelegate else {
            completionHandler(false)
            return
        }
        appDelegate.handleShortcutItem(shortcutItem, completionHandler: completionHandler)
    }
}
