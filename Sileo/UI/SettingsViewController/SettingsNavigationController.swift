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
            // 让 iOS 26 保留系统导航栏的 Liquid Glass，而不是换成旧的图片背景。
            navigationBar.isTranslucent = true
            navigationBar.backgroundColor = .clear
            navigationBar.barTintColor = nil
            navigationBar.setBackgroundImage(nil, for: .default)
            navigationBar.shadowImage = nil
            return
        }

        let isSettings = viewController.isKind(of: BaseSettingsViewController.self)
        let backgroundImage = UINavigationBar.appearance().backgroundImage(for: UIBarMetrics.default)
        
        self.navigationBar.setBackgroundImage(isSettings ? UIImage() : backgroundImage, for: UIBarMetrics.default)
        self.navigationBar.barTintColor = isSettings ? UIColor.clear : UINavigationBar.appearance().barTintColor
        self.navigationBar.shadowImage = isSettings ? UIImage() : UINavigationBar.appearance().shadowImage
    }
}
