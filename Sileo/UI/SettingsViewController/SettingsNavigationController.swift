//
//  SettingsNavigationController.swift
//  Sileo
//
//  Created by Skitty on 1/26/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

class SettingsNavigationController: UINavigationController, UINavigationControllerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
        self.modalPresentationStyle = UIModalPresentationStyle.formSheet
    }
    
    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        if #available(iOS 26.0, *) {
            // 不再设置背景图片、barTintColor 或 shadowImage，让 UIKit 使用原生 Liquid Glass。
            navigationBar.isTranslucent = true
            if let tableViewController = viewController as? UITableViewController {
                SileoGlass.configureScrollSurface(tableViewController.tableView,
                                                  in: tableViewController)
            }
            return
        }

        let isSettings = viewController.isKind(of: BaseSettingsViewController.self)
        let backgroundImage = UINavigationBar.appearance().backgroundImage(for: UIBarMetrics.default)
        
        self.navigationBar.setBackgroundImage(isSettings ? UIImage() : backgroundImage, for: UIBarMetrics.default)
        self.navigationBar.barTintColor = isSettings ? UIColor.clear : UINavigationBar.appearance().barTintColor
        self.navigationBar.shadowImage = isSettings ? UIImage() : UINavigationBar.appearance().shadowImage
    }
}
