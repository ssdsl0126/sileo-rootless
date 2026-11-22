//
//  SileoNavigationController.swift
//  Sileo
//
//  Created by CoolStar on 7/27/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

class SileoNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? {
        viewControllers.last
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if #available(iOS 26.0, *) {
            TabBarController.singleton?.restoreModernPadTraitsIfNeeded(for: viewControllerToPresent)
        }
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
}
