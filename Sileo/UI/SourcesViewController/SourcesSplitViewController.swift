//
//  SourcesSplitViewController.swift
//  Sileo
//
//  Created by CoolStar on 1/2/21.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

class SourcesSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate {
    private let minimumVisiblePackageDetailWidth: CGFloat = 760
    private var displayModeBeforePackageDetail: UISplitViewController.DisplayMode?
    private var automaticallyHidPrimaryForPackageDetail = false

    private var detailNavigationController: UINavigationController? {
        guard viewControllers.count > 1 else {
            return nil
        }
        return viewControllers.last as? UINavigationController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.delegate = self
        self.title = String(localizationKey: "Sources_Page")

        if #available(iOS 26.0, *),
           UIDevice.current.userInterfaceIdiom == .pad,
           style != .unspecified {
            preferredDisplayMode = .oneBesideSecondary
            preferredSplitBehavior = .tile
            minimumPrimaryColumnWidth = 260
            maximumPrimaryColumnWidth = 320
            preferredPrimaryColumnWidthFraction = 0.3
            primaryBackgroundStyle = .sidebar
            presentsWithGesture = true
            configurePackageDetailNavigation()
        } else {
            preferredDisplayMode = .allVisible
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if #available(iOS 26.0, *) {
            configurePackageDetailNavigation()
            updatePrimaryVisibilityForCurrentDetail(animated: false)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard #available(iOS 26.0, *),
              UIDevice.current.userInterfaceIdiom == .pad else {
            return
        }

        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updatePrimaryVisibilityForCurrentDetail(availableWidth: size.width, animated: true)
        })
    }

    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        super.showDetailViewController(vc, sender: sender)

        guard #available(iOS 26.0, *),
              UIDevice.current.userInterfaceIdiom == .pad else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.configurePackageDetailNavigation()
            self?.updatePrimaryVisibilityForCurrentDetail(animated: false)
        }
    }
    
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        if secondaryViewController is UINavigationController {
            return false
        }
        return true
    }
    
    override var childForStatusBarStyle: UIViewController? {
        if isCollapsed {
            return viewControllers.last
        } else {
            return viewControllers.first
        }
    }
    
    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        if let navController = viewControllers.first as? UINavigationController {
            navController.navigationBar.tintColor = UINavigationBar.appearance().tintColor
            navController.navigationBar._backgroundOpacity = 1
        }

        if #available(iOS 26.0, *) {
            configurePackageDetailNavigation()
            updatePrimaryVisibilityForCurrentDetail(animated: false)
        }
    }

    @available(iOS 26.0, *)
    private func configurePackageDetailNavigation() {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              let detailNavigationController else {
            return
        }

        if detailNavigationController.delegate !== self {
            detailNavigationController.delegate = self
        }
    }

    @available(iOS 26.0, *)
    private func updatePrimaryVisibilityForCurrentDetail(availableWidth: CGFloat? = nil,
                                                         animated: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              !isCollapsed,
              let detailNavigationController,
              let visibleViewController = detailNavigationController.visibleViewController else {
            return
        }

        let isPackageDetail = visibleViewController is PackageActions

        guard isPackageDetail else {
            restorePrimaryAfterPackageDetailIfNeeded(animated: animated)
            return
        }

        let splitWidth = availableWidth ?? view.bounds.width
        let estimatedPrimaryWidth = max(primaryColumnWidth,
                                        min(maximumPrimaryColumnWidth,
                                            splitWidth * preferredPrimaryColumnWidthFraction))
        let shouldHidePrimary = splitWidth - estimatedPrimaryWidth < minimumVisiblePackageDetailWidth

        if shouldHidePrimary {
            // 用户已经手动收起侧栏时，不把它记作自动收起；离开详情后应保持现状。
            guard displayMode != .secondaryOnly,
                  !automaticallyHidPrimaryForPackageDetail else {
                return
            }
            displayModeBeforePackageDetail = displayMode
            automaticallyHidPrimaryForPackageDetail = true
            setPreferredDisplayMode(.secondaryOnly, animated: animated)
        } else {
            restorePrimaryAfterPackageDetailIfNeeded(animated: animated)
        }
    }

    @available(iOS 26.0, *)
    private func restorePrimaryAfterPackageDetailIfNeeded(animated: Bool) {
        guard automaticallyHidPrimaryForPackageDetail else {
            return
        }

        let previousDisplayMode = displayModeBeforePackageDetail ?? .oneBesideSecondary
        automaticallyHidPrimaryForPackageDetail = false
        displayModeBeforePackageDetail = nil
        setPreferredDisplayMode(previousDisplayMode, animated: animated)
    }

    @available(iOS 26.0, *)
    private func setPreferredDisplayMode(_ displayMode: UISplitViewController.DisplayMode,
                                         animated: Bool) {
        let changes = {
            self.preferredDisplayMode = displayMode
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        guard #available(iOS 26.0, *),
              navigationController === detailNavigationController else {
            return
        }

        updatePrimaryVisibilityForCurrentDetail(animated: animated)
    }
}
