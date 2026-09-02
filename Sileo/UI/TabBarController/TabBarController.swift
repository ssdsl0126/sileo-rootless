//
//  TabBarController.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import LNPopupController

class TabBarController: UITabBarController, UITabBarControllerDelegate, UIAdaptivePresentationControllerDelegate {
    static var singleton: TabBarController?
    private var downloadsController: UINavigationController?
    private(set) public var popupIsPresented = false
    private var popupLock = DispatchSemaphore(value: 1)
    private var shouldSelectIndex = -1
    private var fuckedUpSources = false
    private var popupTapGesture: UITapGestureRecognizer?
    private var popupTapCatcher: UIControl?
    private var liquidGlassQueueBar: LiquidGlassQueueBar?
    private var liquidGlassPopupBackgroundView: UIVisualEffectView?
    private var isPresentingQueueSheet = false
    private var isQueueSheetVisible = false

    var isQueuePresentationVisible: Bool {
        popupIsPresented ||
        isPresentingQueueSheet ||
        isQueueSheetVisible ||
        presentedViewController === downloadsController
    }
    
    private var preferredPopupInteractionStyle: LNPopupInteractionStyle {
        UIDevice.current.userInterfaceIdiom == .phone ? .snap : .drag
    }

    private var usesFloatingQueueCardOnPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var queueCollapsedInteractionStyle: LNPopupInteractionStyle {
        usesFloatingQueueCardOnPhone ? .none : preferredPopupInteractionStyle
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        delegate = self
        TabBarController.singleton = self
        
        downloadsController = UINavigationController(rootViewController: DownloadManager.shared.viewController)
        downloadsController?.isNavigationBarHidden = true
        downloadsController?.view.backgroundColor = .sileoBackgroundColor
        downloadsController?.view.isOpaque = true
        downloadsController?.popupItem.title = ""
        downloadsController?.popupItem.subtitle = ""
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        updateSileoColors()
        updateLiquidGlassTabBarMinimizeBehavior()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            registerLiquidGlassContentScrollView()
        }
        
        self.updatePopup()
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        shouldSelectIndex = tabBarController.selectedIndex
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if shouldSelectIndex == tabBarController.selectedIndex {
            if let splitViewController = viewController as? UISplitViewController {
                if let navController = splitViewController.viewControllers[0] as? UINavigationController {
                    navController.popToRootViewController(animated: true)
                }
            }
        }
        if tabBarController.selectedIndex == 4 && shouldSelectIndex == 4 {
            if let navController = tabBarController.viewControllers?[4] as? SileoNavigationController,
               let packageList = navController.viewControllers[0] as? PackageListViewController {
                packageList.searchController.searchBar.becomeFirstResponder()
            }
        }
        if tabBarController.selectedIndex == 3 && shouldSelectIndex == 3 {
            if let navController = tabBarController.viewControllers?[3] as? SileoNavigationController,
               let packageList = navController.viewControllers[0] as? PackageListViewController,
               let collectionView = packageList.collectionView {
                let yVal = -1 * collectionView.adjustedContentInset.top
                collectionView.setContentOffset(CGPoint(x: 0, y: yVal), animated: true)
            }
        }
        if tabBarController.selectedIndex ==  2 && !fuckedUpSources {
            if let sourcesSVC = tabBarController.viewControllers?[2] as? UISplitViewController,
               let sourcesNaVC = sourcesSVC.viewControllers[0] as? SileoNavigationController {
                if sourcesNaVC.presentedViewController == nil {
                    sourcesNaVC.popToRootViewController(animated: false)
                }
            }
            fuckedUpSources = true
        }
        if viewController as? SileoNavigationController != nil { return }
        if viewController as? SourcesSplitViewController != nil { return }
        fatalError("View Controller mismatch")
    }
    
    func presentPopup() {
        presentPopup(completion: nil)
    }
    
    func presentPopup(completion: (() -> Void)?) {
        if usesFloatingQueueCardOnPhone, (isQueueSheetVisible || isPresentingQueueSheet) {
            completion?()
            return
        }

        guard let downloadsController = downloadsController,
              !popupIsPresented
        else {
            if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone, popupIsPresented {
                // 队列已经存在时，新增或移除软件包不会再次创建 accessory，直接刷新两行文案。
                updateLiquidGlassQueueBar()
            }
            if let completion = completion {
                completion()
            }
            return
        }
        
        popupLock.wait()
        defer {
            popupLock.signal()
        }
        
        popupIsPresented = true
        updateLiquidGlassTabBarMinimizeBehavior()
        if let queueVC = downloadsController.viewControllers.first as? DownloadsTableViewController {
            queueVC.usesSystemQueueSheetPresentation = false
        }

        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            presentLiquidGlassQueueBar()
            updateSileoColors()
            completion?()
            return
        }

        self.popupBar.progressViewStyle = .bottom
        self.popupInteractionStyle = queueCollapsedInteractionStyle
        self.presentPopupBar(withContentViewController: downloadsController, animated: true, completion: completion)
        self.configurePopupTapIfNeeded()
        
        self.updateSileoColors()
    }
    
    func dismissPopup() {
        dismissPopup(completion: nil)
    }
    
    func dismissPopup(completion: (() -> Void)?) {
        guard popupIsPresented else {
            if let completion = completion {
                completion()
            }
            return
        }
        
        popupLock.wait()
        defer {
            popupLock.signal()
        }
        
        popupIsPresented = false
        updateLiquidGlassTabBarMinimizeBehavior()
        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            removeLiquidGlassQueueBar()
            completion?()
            return
        }
        if #available(iOS 26.0, *) {
            removePopupTapCatcher()
        }
        self.dismissPopupBar(animated: true, completion: completion)
    }
    
    func presentPopupController() {
        self.presentPopupController(completion: nil)
    }
    
    func presentPopupController(completion: (() -> Void)?) {
        if usesFloatingQueueCardOnPhone {
            presentSystemQueueSheet(completion: completion)
            return
        }

        guard popupIsPresented else {
            if let completion = completion {
                completion()
            }
            return
        }
        
        popupLock.wait()
        defer {
            popupLock.signal()
        }
        
        self.popupInteractionStyle = preferredPopupInteractionStyle
        self.openPopup(animated: true, completion: completion)
    }
    
    func dismissPopupController() {
        self.dismissPopupController(completion: nil)
    }
    
    func dismissPopupController(completion: (() -> Void)?) {
        if usesFloatingQueueCardOnPhone,
           isQueueSheetVisible,
           let downloadsController = downloadsController,
           downloadsController.presentingViewController != nil {
            downloadsController.dismiss(animated: true) {
                self.isQueueSheetVisible = false
                self.isPresentingQueueSheet = false
                self.updatePopup()
                completion?()
            }
            return
        }

        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone, popupIsPresented {
            dismissPopup(completion: completion)
            return
        }

        guard popupIsPresented else {
            completion?()
            return
        }
        
        popupLock.wait()
        defer {
            popupLock.signal()
        }
        
        self.closePopup(animated: true, completion: completion)
    }
    
    func updatePopup() {
        updatePopup(completion: nil)
    }
    
    func updatePopup(completion: (() -> Void)? = nil, bypass: Bool = false) {
        if isQueueSheetVisible || isPresentingQueueSheet {
            completion?()
            return
        }

        func hideRegardless() {
            if UIDevice.current.userInterfaceIdiom == .pad && self.view.frame.width >= 768 {
                downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), 0)
                self.presentPopup(completion: completion)
            } else {
                self.dismissPopup(completion: completion)
            }
        }
        if bypass {
            hideRegardless()
            return
        }
        let manager = DownloadManager.shared
        if manager.lockedForInstallation {
            downloadsController?.popupItem.title = String(localizationKey: "Installing_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.readyPackages())
            downloadsController?.popupItem.progress = Float(manager.totalProgress)
            self.presentPopup(completion: completion)
        } else if manager.downloadingPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Downloading_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.downloadingPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else if manager.operationCount() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.operationCount())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else if manager.readyPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Ready_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.readyPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else if manager.uninstallingPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Removal_Queued_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.uninstallingPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else {
            hideRegardless()
        }
    }
    
    override var bottomDockingViewForPopupBar: UIView? {
        self.tabBar
    }
    
    override var defaultFrameForBottomDockingView: CGRect {
        var tabBarFrame = self.tabBar.frame
        tabBarFrame.origin.y = self.view.bounds.height - tabBarFrame.height
        if UIDevice.current.userInterfaceIdiom == .pad {
            tabBarFrame.origin.x = 0
            tabBarFrame.size.width = self.view.bounds.width
            if tabBarFrame.width >= 768 {
                tabBarFrame.size.width -= 320
            }
        }
        return tabBarFrame
    }
    
    override var insetsForBottomDockingView: UIEdgeInsets {
        if UIDevice.current.userInterfaceIdiom == .pad {
            if self.view.bounds.width < 768 {
                return .zero
            }
            return UIEdgeInsets(top: self.tabBar.frame.height, left: self.view.bounds.width - 320, bottom: 0, right: 0)
        }
        return .zero
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateSileoColors()
        guard popupIsPresented else {
            return
        }
        popupInteractionStyle = queueCollapsedInteractionStyle
    }

    public func restoreQueueCollapsedInteractionStyle() {
        popupInteractionStyle = queueCollapsedInteractionStyle
    }

    func updateLiquidGlassScroll(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *),
              usesFloatingQueueCardOnPhone,
              popupIsPresented,
              !isQueueSheetVisible,
              !isPresentingQueueSheet else {
            return
        }

        // 当前页面可能是导航栈里的详情页，把实际滚动视图直接交给标签栏控制器和导航容器，
        // 让 UIKit 的 iOS 26 收缩手势跟踪当前页面，而不是依赖固定的初始页面。
        setContentScrollView(scrollView, for: .top)
        setContentScrollView(scrollView, for: .bottom)
        selectedViewController?.setContentScrollView(scrollView, for: .top)
        selectedViewController?.setContentScrollView(scrollView, for: .bottom)
    }

    @available(iOS 26.0, *)
    private func registerLiquidGlassContentScrollView() {
        guard let selectedViewController,
              let scrollView = liquidGlassContentScrollView(in: selectedViewController) else {
            return
        }

        setContentScrollView(scrollView, for: .top)
        setContentScrollView(scrollView, for: .bottom)
        selectedViewController.setContentScrollView(scrollView, for: .top)
        selectedViewController.setContentScrollView(scrollView, for: .bottom)
    }

    @available(iOS 26.0, *)
    private func liquidGlassContentScrollView(in viewController: UIViewController) -> UIScrollView? {
        if let scrollView = viewController.contentScrollView(for: .bottom) {
            return scrollView
        }

        if let navigationController = viewController as? UINavigationController,
           let topViewController = navigationController.topViewController {
            return liquidGlassContentScrollView(in: topViewController)
        }

        if let splitViewController = viewController as? UISplitViewController {
            for childViewController in splitViewController.viewControllers {
                if let scrollView = liquidGlassContentScrollView(in: childViewController) {
                    return scrollView
                }
            }
        }

        for childViewController in viewController.children {
            if let scrollView = liquidGlassContentScrollView(in: childViewController) {
                return scrollView
            }
        }

        return nil
    }

    private func configurePopupTapIfNeeded() {
        guard usesFloatingQueueCardOnPhone else {
            removePopupTapCatcher()
            return
        }

        if #available(iOS 26.0, *) {
            // iOS 26 的 popupBar 内部手势会被玻璃子视图拦截，使用宿主视图上的透明控件承接点击。
            for recognizer in popupBar.gestureRecognizers ?? [] {
                recognizer.isEnabled = false
            }
            popupTapGesture?.isEnabled = false

            if popupTapCatcher == nil {
                let catcher = UIControl(frame: .zero)
                catcher.backgroundColor = .clear
                catcher.accessibilityLabel = "Package Queue"
                catcher.accessibilityTraits = .button
                catcher.addTarget(self, action: #selector(handlePopupBarTap), for: .touchUpInside)
                popupTapCatcher = catcher
            }

            if let popupTapCatcher = popupTapCatcher {
                let frame = popupBar.convert(popupBar.bounds, to: view)
                popupTapCatcher.frame = frame
                if popupTapCatcher.superview !== view {
                    popupTapCatcher.removeFromSuperview()
                    view.addSubview(popupTapCatcher)
                }
                view.bringSubviewToFront(popupTapCatcher)
            }
            return
        }

        if let recognizers = popupBar.gestureRecognizers {
            for recognizer in recognizers where recognizer !== popupTapGesture {
                recognizer.isEnabled = false
            }
        }

        if popupTapGesture == nil {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handlePopupBarTap))
            gesture.cancelsTouchesInView = true
            popupTapGesture = gesture
            popupBar.addGestureRecognizer(gesture)
        }

        if popupTapCatcher == nil {
            let catcher = UIControl(frame: popupBar.bounds)
            catcher.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            catcher.backgroundColor = .clear
            catcher.addTarget(self, action: #selector(handlePopupBarTap), for: .touchUpInside)
            popupTapCatcher = catcher
        }
        if let popupTapCatcher = popupTapCatcher {
            popupTapCatcher.frame = popupBar.bounds
            if popupTapCatcher.superview !== popupBar {
                popupBar.addSubview(popupTapCatcher)
            }
            popupBar.bringSubviewToFront(popupTapCatcher)
        }
    }

    private func removePopupTapCatcher() {
        popupTapCatcher?.removeFromSuperview()
        popupTapCatcher = nil
    }

    @objc private func handlePopupBarTap() {
        guard usesFloatingQueueCardOnPhone,
              popupIsPresented,
              !isQueueSheetVisible,
              !isPresentingQueueSheet
        else {
            return
        }
        presentPopupController()
    }

    private func presentSystemQueueSheet(completion: (() -> Void)?) {
        guard usesFloatingQueueCardOnPhone,
              popupIsPresented,
              !isPresentingQueueSheet,
              !isQueueSheetVisible,
              downloadsController != nil
        else {
            completion?()
            return
        }

        isPresentingQueueSheet = true
        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            // 保留 bottomAccessory，让系统在 sheet 关闭后恢复原来的展开/紧凑位置。
            presentQueueSheet(completion: completion)
        } else {
            popupIsPresented = false
            updateLiquidGlassTabBarMinimizeBehavior()
            dismissPopupBar(animated: false) { [weak self] in
                self?.presentQueueSheet(completion: completion)
            }
        }
    }

    private func presentQueueSheet(completion: (() -> Void)?) {
        guard let downloadsController = downloadsController else {
            isPresentingQueueSheet = false
            return
        }

        if let queueVC = downloadsController.viewControllers.first as? DownloadsTableViewController {
            queueVC.usesSystemQueueSheetPresentation = true
            queueVC.reloadData()
        }
        downloadsController.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = downloadsController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 22
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
        }

        present(downloadsController, animated: true) {
            downloadsController.presentationController?.delegate = self
            self.isQueueSheetVisible = true
            self.isPresentingQueueSheet = false
            completion?()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard usesFloatingQueueCardOnPhone,
              let downloadsController = downloadsController,
              presentationController.presentedViewController === downloadsController
        else {
            return
        }
        isQueueSheetVisible = false
        isPresentingQueueSheet = false
        updatePopup()
    }
    
    @objc func updateSileoColors() {
        self.popupBar.tintColor = UINavigationBar.appearance().tintColor
        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            updateLiquidGlassQueueBar()
        } else if #available(iOS 26.0, *) {
            applyLiquidGlassPopupAppearance()
        }
        if self.responds(to: NSSelectorFromString("setNeedsPopupBarAppearanceUpdate")) {
            _ = self.perform(NSSelectorFromString("setNeedsPopupBarAppearanceUpdate"))
        }
    }

    private func updateLiquidGlassTabBarMinimizeBehavior() {
        guard #available(iOS 26.0, *), usesFloatingQueueCardOnPhone else {
            return
        }
        // 只有存在队列时启用系统收缩；队列消失后恢复完整标签栏。
        // 当前页面列表下滑时进入胶囊紧凑态。
        tabBarMinimizeBehavior = popupIsPresented ? .onScrollDown : .never
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.tabBar.itemPositioning = .centered
        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            // accessory 的首次布局可能会重建标签栏，布局完成后再次保持当前策略。
            tabBarMinimizeBehavior = popupIsPresented ? .onScrollDown : .never
        } else if usesFloatingQueueCardOnPhone {
            configurePopupTapIfNeeded()
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.updatePopup()
        }
    }

    @available(iOS 26.0, *)
    private func presentLiquidGlassQueueBar() {
        let queueBar: LiquidGlassQueueBar
        if let existingBar = liquidGlassQueueBar {
            queueBar = existingBar
        } else {
            let createdBar = LiquidGlassQueueBar(frame: .zero)
            createdBar.addTarget(self, action: #selector(handlePopupBarTap), for: .touchUpInside)
            liquidGlassQueueBar = createdBar
            queueBar = createdBar
        }

        queueBar.update(title: downloadsController?.popupItem.title,
                        subtitle: downloadsController?.popupItem.subtitle)
        queueBar.isHidden = false
        setBottomAccessory(UITabAccessory(contentView: queueBar), animated: false)
        tabBarMinimizeBehavior = .onScrollDown
    }

    @available(iOS 26.0, *)
    private func updateLiquidGlassQueueBar() {
        liquidGlassQueueBar?.update(title: downloadsController?.popupItem.title,
                                    subtitle: downloadsController?.popupItem.subtitle)
    }

    @available(iOS 26.0, *)
    private func removeLiquidGlassQueueBar() {
        setBottomAccessory(nil, animated: false)
        liquidGlassQueueBar?.isHidden = true
        liquidGlassQueueBar?.removeFromSuperview()
    }

    @available(iOS 26.0, *)
    private func applyLiquidGlassPopupAppearance() {
        // LNPopupController 的旧背景会在布局时重新写入 UIBlurEffect，先将它清空。
        popupBar.inheritsVisualStyleFromDockingView = false
        popupBar.isTranslucent = true
        popupBar.systemBarStyle = .default
        popupBar.barTintColor = .clear
        popupBar.backgroundColor = .clear
        popupBar.titleTextAttributes = [.foregroundColor: UIColor.sileoLabel]
        popupBar.subtitleTextAttributes = [.foregroundColor: UIColor.sileoLabel.withAlphaComponent(0.72)]

        if let legacyBackgroundView = popupBar.subviews.compactMap({ $0 as? UIVisualEffectView }).first(where: {
            $0.accessibilityIdentifier == "PopupBarView"
        }) {
            legacyBackgroundView.effect = nil
            legacyBackgroundView.backgroundColor = .clear
        }

        let glassBackground: UIVisualEffectView
        if let existingView = liquidGlassPopupBackgroundView {
            glassBackground = existingView
        } else {
            let createdView = UIVisualEffectView(effect: nil)
            createdView.isUserInteractionEnabled = false
            liquidGlassPopupBackgroundView = createdView
            glassBackground = createdView
        }

        glassBackground.frame = popupBar.bounds
        glassBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if glassBackground.superview !== popupBar {
            glassBackground.removeFromSuperview()
            popupBar.insertSubview(glassBackground, at: min(1, popupBar.subviews.count))
        }
        SileoGlass.update(glassBackground,
                          tintColor: UIColor.sileoBackgroundColor.withAlphaComponent(0.22))
        glassBackground.backgroundColor = .clear

        // popupBar 的标题由第三方控件创建，直接刷新其实际 label 的颜色，避免出现深色背景配白字。
        func updateLabelColors(in view: UIView) {
            for subview in view.subviews {
                if let label = subview as? UILabel, label.text != nil {
                    label.textColor = UIColor.sileoLabel
                }
                updateLabelColors(in: subview)
            }
        }
        updateLabelColors(in: popupBar)
    }
    
    public func displayError(_ string: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.displayError(string)
            }
            return
        }
        let alertController = UIAlertController(title: String(localizationKey: "Unknown", type: .error), message: string, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .default))
        self.present(alertController, animated: true, completion: nil)
    }
}

private final class LiquidGlassQueueBar: UIControl {
    private let glassView: UIVisualEffectView
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        glassView = UIVisualEffectView(effect: SileoGlass.effect(interactive: true,
                                                                 tintColor: UIColor.sileoBackgroundColor.withAlphaComponent(0.18)))
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = true
        layer.masksToBounds = true
        glassView.isUserInteractionEnabled = false
        glassView.clipsToBounds = true
        addSubview(glassView)

        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.isUserInteractionEnabled = false
        titleLabel.layer.zPosition = 1
        addSubview(titleLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        subtitleLabel.textColor = .label
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.8
        subtitleLabel.isUserInteractionEnabled = false
        subtitleLabel.layer.zPosition = 1
        addSubview(subtitleLabel)

        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 64)
    }

    func update(title: String?, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        // 队列文案使用系统标签色并保持不透明，避免自定义主题色与玻璃背景对比不足。
        titleLabel.textColor = .label
        subtitleLabel.textColor = .label
        glassView.effect = SileoGlass.effect(interactive: true,
                                              tintColor: UIColor.sileoBackgroundColor.withAlphaComponent(0.18))
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        let cornerRadius = min(bounds.width, bounds.height) / 2
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.layer.masksToBounds = true
        let isInlineEnvironment: Bool
        if #available(iOS 26.0, *) {
            isInlineEnvironment = traitCollection.tabAccessoryEnvironment == .inline
        } else {
            isInlineEnvironment = false
        }
        let isCompactHeight = isInlineEnvironment || bounds.height < 56
        titleLabel.font = UIFont.systemFont(ofSize: isCompactHeight ? 12 : 13,
                                             weight: .regular)
        subtitleLabel.font = UIFont.systemFont(ofSize: isCompactHeight ? 16 : 17,
                                                weight: .semibold)
        let horizontalInset = min(22, max(14, bounds.width * 0.06))
        let titleHeight = ceil(titleLabel.font.lineHeight)
        let subtitleHeight = ceil(subtitleLabel.font.lineHeight)
        let verticalGap: CGFloat = isCompactHeight ? 3 : 4
        let contentHeight = titleHeight + verticalGap + subtitleHeight
        let verticalInset = max(5, (bounds.height - contentHeight) / 2)
        titleLabel.frame = CGRect(x: horizontalInset,
                                  y: verticalInset,
                                  width: max(0, bounds.width - (horizontalInset * 2)),
                                  height: titleHeight)
        subtitleLabel.frame = CGRect(x: horizontalInset,
                                     y: titleLabel.frame.maxY + verticalGap,
                                     width: max(0, bounds.width - (horizontalInset * 2)),
                                     height: subtitleHeight)
        bringSubviewToFront(titleLabel)
        bringSubviewToFront(subtitleLabel)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
    }
}

private final class QueueFloatingCardController: UIViewController, UIGestureRecognizerDelegate {
    private let contentController: UIViewController
    private let dimmingView = UIControl(frame: .zero)
    private let cardContainerView = UIView(frame: .zero)
    private let grabberView = UIView(frame: .zero)
    private var panGesture: UIPanGestureRecognizer?
    private var didAnimateIn = false
    private var isDismissing = false
    private let baseDimmingAlpha: CGFloat = 0.72
    private weak var primaryScrollView: UIScrollView?
    var onDismiss: (() -> Void)?

    init(contentController: UIViewController) {
        self.contentController = contentController
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        dimmingView.alpha = 0
        dimmingView.addTarget(self, action: #selector(dismissByTap), for: .touchUpInside)
        view.addSubview(dimmingView)

        cardContainerView.translatesAutoresizingMaskIntoConstraints = false
        cardContainerView.backgroundColor = .sileoBackgroundColor
        cardContainerView.layer.cornerRadius = 26
        if #available(iOS 13.0, *) {
            cardContainerView.layer.cornerCurve = .continuous
        }
        cardContainerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardContainerView.layer.masksToBounds = true
        view.addSubview(cardContainerView)

        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.backgroundColor = UIColor.systemGray2
        grabberView.layer.cornerRadius = 2.5
        cardContainerView.addSubview(grabberView)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleCardPan(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        cardContainerView.addGestureRecognizer(panGesture)
        self.panGesture = panGesture

        addChild(contentController)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        cardContainerView.addSubview(contentController.view)
        contentController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 84),
            cardContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            grabberView.topAnchor.constraint(equalTo: cardContainerView.topAnchor, constant: 8),
            grabberView.centerXAnchor.constraint(equalTo: cardContainerView.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 44),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            contentController.view.leadingAnchor.constraint(equalTo: cardContainerView.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: cardContainerView.trailingAnchor),
            contentController.view.topAnchor.constraint(equalTo: cardContainerView.topAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: cardContainerView.bottomAnchor)
        ])

        cardContainerView.transform = CGAffineTransform(translationX: 0, y: 180)
        cardContainerView.alpha = 0
        primaryScrollView = findPrimaryScrollView(in: contentController.view)
    }

    private func findPrimaryScrollView(in rootView: UIView?) -> UIScrollView? {
        guard let rootView = rootView else {
            return nil
        }
        if let scrollView = rootView as? UIScrollView {
            return scrollView
        }
        for subview in rootView.subviews {
            if let scrollView = findPrimaryScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func isScrollViewPinnedToTop(_ scrollView: UIScrollView?) -> Bool {
        guard let scrollView = scrollView else {
            return true
        }
        let topOffset = -scrollView.adjustedContentInset.top
        return scrollView.contentOffset.y <= topOffset + 1
    }

    private func pinScrollViewToTop(_ scrollView: UIScrollView?) {
        guard let scrollView = scrollView else {
            return
        }
        let topOffset = -scrollView.adjustedContentInset.top
        if scrollView.contentOffset.y > topOffset {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: topOffset)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        UIView.animate(withDuration: 0.26, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
            self.dimmingView.alpha = self.baseDimmingAlpha
            self.cardContainerView.alpha = 1
            self.cardContainerView.transform = .identity
        })
    }

    @objc private func dismissByTap() {
        dismissCard(completion: nil)
    }

    @objc private func handleCardPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else {
            return
        }

        let translation = gesture.translation(in: view)
        let offsetY = max(0, translation.y)
        let progress = min(1, offsetY / 220)
        let scrollView = primaryScrollView
        let canDragCardDown = isScrollViewPinnedToTop(scrollView)

        switch gesture.state {
        case .changed:
            if offsetY <= 0 {
                return
            }

            guard canDragCardDown || cardContainerView.transform.ty > 0 else {
                return
            }
            pinScrollViewToTop(scrollView)
            cardContainerView.transform = CGAffineTransform(translationX: 0, y: offsetY)
            dimmingView.alpha = baseDimmingAlpha * (1 - (progress * 0.85))
        case .ended, .cancelled:
            if cardContainerView.transform.ty <= 0 {
                return
            }
            let velocityY = gesture.velocity(in: view).y
            let shouldDismiss = offsetY > 140 || velocityY > 1250
            if shouldDismiss {
                dismissCard(completion: nil)
            } else {
                UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
                    self.cardContainerView.transform = .identity
                    self.dimmingView.alpha = self.baseDimmingAlpha
                })
            }
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer
        else {
            return true
        }

        let velocity = pan.velocity(in: cardContainerView)
        guard velocity.y > abs(velocity.x), velocity.y > 0 else {
            return false
        }
        return isScrollViewPinnedToTop(primaryScrollView) || cardContainerView.transform.ty > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else {
            return false
        }
        return otherGestureRecognizer.view is UIScrollView || otherGestureRecognizer == (otherGestureRecognizer.view as? UIScrollView)?.panGestureRecognizer
    }

    func dismissCard(completion: (() -> Void)?) {
        guard !isDismissing else {
            completion?()
            return
        }
        isDismissing = true
        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
            self.dimmingView.alpha = 0
            self.cardContainerView.alpha = 0
            self.cardContainerView.transform = CGAffineTransform(translationX: 0, y: 180)
        }, completion: { _ in
            self.dismiss(animated: false) {
                self.onDismiss?()
                completion?()
            }
        })
    }
}
