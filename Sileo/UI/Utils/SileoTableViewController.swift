//
//  SileoTableViewController.swift
//  Sileo
//
//  Created by CoolStar on 7/27/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

class SileoTableViewController: UITableViewController {
    var statusBarStyle: UIStatusBarStyle = .default {
        didSet {
            var style = statusBarStyle
            if style == .default {
                if SileoThemeManager.shared.currentTheme.preferredUserInterfaceStyle == .dark {
                    style = .lightContent
                } else if SileoThemeManager.shared.currentTheme.preferredUserInterfaceStyle == .light {
                    if #available(iOS 13.0, *) {
                        style = .darkContent
                    }
                }
            }
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if statusBarStyle == .default {
            if SileoThemeManager.shared.currentTheme.preferredUserInterfaceStyle == .dark {
                return .lightContent
            } else if SileoThemeManager.shared.currentTheme.preferredUserInterfaceStyle == .light {
                if #available(iOS 13.0, *) {
                    return .darkContent
                }
            }
        }
        return statusBarStyle
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if #available(iOS 26.0, *) {
            TabBarController.singleton?.restoreModernPadTraitsIfNeeded(for: viewControllerToPresent)
        }
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
}
