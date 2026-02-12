//
//  SileoViewController.swift
//  Sileo
//
//  Created by CoolStar on 7/27/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

public class SileoViewController: UIViewController {
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
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
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
    
    func normalizeLargeTitleLayoutMargins(leading: CGFloat = 20) {
        guard Thread.isMainThread,
              #available(iOS 11.0, *),
              let navigationBar = navigationController?.navigationBar,
              navigationBar.prefersLargeTitles else {
            return
        }

        if SileoRuntimeEnvironment.isLargeTitleMarginNormalizationDisabled {
            SileoRuntimeEnvironment.logLargeTitleMarginNormalizationDisabledByUserDefaultsIfNeeded()
            return
        }

        if SileoRuntimeEnvironment.hasThirdPartyTweakInjection {
            SileoRuntimeEnvironment.logLargeTitleMarginNormalizationDisabledByTweakInjectionIfNeeded()
            return
        }

        if navigationBar.insetsLayoutMarginsFromSafeArea != true {
            navigationBar.insetsLayoutMarginsFromSafeArea = true
        }

        var layoutMargins = navigationBar.layoutMargins
        if layoutMargins.left != leading || layoutMargins.right != leading {
            layoutMargins.left = leading
            layoutMargins.right = leading
            navigationBar.layoutMargins = layoutMargins
        }
    }
}
