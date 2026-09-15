//
//  SourcesSplitViewController.swift
//  Sileo
//
//  Created by CoolStar on 1/2/21.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

class SourcesSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate {
    private var displayModeBeforePackageDetail: UISplitViewController.DisplayMode?
    private var isTrackingPackageDetailVisibility = false
    private var pendingAutomaticDisplayMode: UISplitViewController.DisplayMode?
    private var isAdaptingToWindowSize = false

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
            // 尚未选择软件源时详情栏为空，首次进入应先展示软件源列表。
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

        isAdaptingToWindowSize = true
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updatePrimaryVisibilityForCurrentDetail(animated: true)
        }, completion: { [weak self] _ in
            self?.isAdaptingToWindowSize = false
        })
    }

    func splitViewController(_ svc: UISplitViewController,
                             willChangeTo displayMode: UISplitViewController.DisplayMode) {
        guard #available(iOS 26.0, *),
              UIDevice.current.userInterfaceIdiom == .pad,
              style != .unspecified else {
            return
        }

        // 自动收起/恢复的通知可能晚于赋值返回，用目标模式识别该次变更。
        if pendingAutomaticDisplayMode == displayMode {
            pendingAutomaticDisplayMode = nil
            return
        }

        guard isTrackingPackageDetailVisibility,
              !isAdaptingToWindowSize,
              !isCollapsed,
              detailNavigationController?.visibleViewController is PackageActions else {
            return
        }

        // 详情内手动开关侧栏后，返回列表应沿用最新选择，而不是进入详情前的状态。
        displayModeBeforePackageDetail = displayMode
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
    private func updatePrimaryVisibilityForCurrentDetail(animated: Bool) {
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

        // 每次进入详情只自动收起一次；后续布局、切换标签不得覆盖手动操作。
        guard !isTrackingPackageDetailVisibility else {
            return
        }
        displayModeBeforePackageDetail = displayMode
        isTrackingPackageDetailVisibility = true
        guard displayMode != .secondaryOnly else {
            return
        }
        setPreferredDisplayMode(.secondaryOnly, animated: animated)

        if #available(iOS 27.0, *) {
            // iPadOS 27: 解决主栏展开后切回 secondaryOnly 导致 secondary 顶部边缘毛玻璃常驻锁定的系统 Bug
            // 重新刷新 secondary 导航控制器的容器关联，重置边缘效果状态机
            setViewController(detailNavigationController, for: .secondary)
        }
    }

    @available(iOS 26.0, *)
    private func restorePrimaryAfterPackageDetailIfNeeded(animated: Bool) {
        guard isTrackingPackageDetailVisibility else {
            return
        }

        let previousDisplayMode = displayModeBeforePackageDetail ?? .oneBesideSecondary
        isTrackingPackageDetailVisibility = false
        displayModeBeforePackageDetail = nil
        setPreferredDisplayMode(previousDisplayMode, animated: animated)
    }

    @available(iOS 26.0, *)
    private func setPreferredDisplayMode(_ displayMode: UISplitViewController.DisplayMode,
                                         animated: Bool) {
        let changes = {
            self.pendingAutomaticDisplayMode = self.displayMode == displayMode ? nil : displayMode
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
