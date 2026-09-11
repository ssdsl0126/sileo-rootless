//
//  TabBarController.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import LNPopupController
import ObjectiveC

class TabBarController: UITabBarController, UITabBarControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private enum LegacyPopupBarState {
        case hidden
        case presenting
        case presented
        case dismissing
    }

    private enum LegacyPopupContentState {
        case closed
        case opening
        case open
        case closing
    }

    static var singleton: TabBarController?
    private var downloadsController: UINavigationController?
    private(set) public var popupIsPresented = false
    private var legacyPopupBarState = LegacyPopupBarState.hidden
    private var legacyPopupContentState = LegacyPopupContentState.closed
    private var shouldPresentLegacyPopupBar = false
    private var shouldOpenLegacyPopupContent: Bool?
    private var legacyPopupPresentationCompletions = [() -> Void]()
    private var legacyPopupDismissalCompletions = [() -> Void]()
    private var legacyPopupOpenCompletions = [() -> Void]()
    private var legacyPopupCloseCompletions = [() -> Void]()
    private var legacyQueueSeparatorExtension: UIView?
    private var shouldSelectIndex = -1
    private var fuckedUpSources = false
    private var popupTapGesture: UITapGestureRecognizer?
    private var popupTapCatcher: UIControl?
    private var liquidGlassQueueBar: LiquidGlassQueueBar?
    private var liquidGlassPopupBackgroundView: UIVisualEffectView?
    private var isPresentingQueueSheet = false
    private var isQueueSheetVisible = false
    private var sourcesQueueIsMinimized = false
    private var sourcesQueueTrackingScrollView: UIScrollView?

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

    private var usesLiquidGlassQueueAccessory: Bool {
        guard #available(iOS 26.0, *) else {
            return false
        }
        let idiom = UIDevice.current.userInterfaceIdiom
        return idiom == .phone || idiom == .pad
    }

    private var usesSystemQueueSheetPresentation: Bool {
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            return true
        }
        return usesFloatingQueueCardOnPhone
    }

    private var queueCollapsedInteractionStyle: LNPopupInteractionStyle {
        usesFloatingQueueCardOnPhone ? .none : preferredPopupInteractionStyle
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        delegate = self
        TabBarController.singleton = self
        (tabBar as? TabBar)?.attachDecorations(to: view)
        prepareSileoTabSelection(sileoSelectedViewController)

        downloadsController = UINavigationController(rootViewController: DownloadManager.shared.viewController)
        downloadsController?.isNavigationBarHidden = true
        downloadsController?.view.backgroundColor = .sileoBackgroundColor
        downloadsController?.view.isOpaque = true
        downloadsController?.popupItem.title = ""
        downloadsController?.popupItem.subtitle = ""
        if UIDevice.current.userInterfaceIdiom == .pad,
           #unavailable(iOS 26.0) {
            // 仅旧版 iPadOS 使用 LNPopup 回调；新系统队列和 iPhone 不启用。
            popupPresentationDelegate = self
        }
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        updateSileoColors()
        updateLiquidGlassTabBarMinimizeBehavior()
    }

    func configureSearchTabIfNeeded() {
        guard #available(iOS 27.0, *),
              UIDevice.current.userInterfaceIdiom == .phone,
              tabs.isEmpty,
              let controllers = super.viewControllers else {
            return
        }

        let previousController = super.selectedViewController
        // iOS 27 需要真正的 UISearchTab 才能指定独立入口，继续复用 storyboard 的导航栈。
        prominentTabIdentifier = UISearchTab.identifier
        setTabs(makeTabs(from: controllers), animated: false)
        let initialTab = tabs.first { $0.viewController === previousController } ?? tabs.first
        // iOS 27 首次选中后才重新计算中文标签高度，在首帧提交前完成各标签的布局。
        UIView.performWithoutAnimation {
            for tab in tabs where !(tab is UISearchTab) {
                selectedTab = tab
                view.layoutIfNeeded()
            }
            selectedTab = initialTab
            view.layoutIfNeeded()
        }
        prepareSileoTabSelection(sileoSelectedViewController)
        registerLiquidGlassContentScrollView()
    }

    @available(iOS 27.0, *)
    private func makeTabs(from controllers: [UIViewController]) -> [UITab] {
        let titleKeys = ["Featured_Page", "News_Page", "Sources_Page", "Packages_Page", "Search_Page"]
        return controllers.enumerated().map { index, controller in
            if let existingTab = controller.tab {
                return existingTab
            }
            let previousItem = controller.tabBarItem!
            let title = titleKeys.indices.contains(index) ? String(localizationKey: titleKeys[index]) : (previousItem.title ?? "")
            let image = normalizedTabImage(previousItem.image)
            let selectedImage = normalizedTabImage(previousItem.selectedImage ?? previousItem.image)
            // UIKit 在过渡动画中也会读取控制器的旧 tabBarItem，保持两套元数据一致。
            let item = UITabBarItem(title: title, image: image, tag: previousItem.tag)
            item.selectedImage = selectedImage
            item.badgeValue = previousItem.badgeValue
            item.badgeColor = previousItem.badgeColor
            controller.tabBarItem = item
            let tab: UITab
            if let navigationController = controller as? UINavigationController,
               let packageList = navigationController.viewControllers.first as? PackageListViewController,
               packageList.showSearchField {
                let searchTab = UISearchTab { _ in controller }
                // 首次进入先展示最近搜索，点搜索框或再次点搜索标签时才弹出键盘。
                searchTab.automaticallyActivatesSearch = false
                tab = searchTab
            } else {
                tab = UITab(title: title, image: image, identifier: "sileo.tab.\(index)") { _ in controller }
            }
            tab.title = title
            tab.image = image ?? tab.image
            tab.selectedImage = selectedImage ?? tab.image
            tab.badgeValue = item.badgeValue
            return tab
        }
    }

    @available(iOS 27.0, *)
    private func normalizedTabImage(_ image: UIImage?) -> UIImage? {
        guard var image else { return nil }
        image = image.withTintColor(.black, renderingMode: .alwaysOriginal)
        if !image.isSymbolImage {
            // 自定义图标使用相同画布，避免 UIKit 按不同图片高度挤压菜单标题。
            let size = CGSize(width: 26, height: 26)
            let bounds = CGRect(origin: CGPoint(x: (size.width - image.size.width) / 2,
                                                y: (size.height - image.size.height) / 2),
                                size: image.size)
            image = UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: bounds)
            }.withBaselineOffset(fromBottom: 0)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        guard let controller = tab.viewController else { return false }
        // 由 UIKit 完成标签与搜索栏的同一次过渡，避免手动切换后再取消选择导致旧菜单残留。
        return self.tabBarController(tabBarController, shouldSelect: controller)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let controller = selectedTab.viewController else { return }
        self.tabBarController(tabBarController, didSelect: controller)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            registerLiquidGlassContentScrollView()
        }
        
        self.updatePopup()
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        shouldSelectIndex = tabBarController.sileoSelectedIndex
        prepareSileoTabSelection(viewController)
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            registerLiquidGlassContentScrollView()
            // iOS 26 在切换顶层标签时会重建滚动观察关系，并可能把收缩策略临时重置为 .never。
            // 等本轮容器布局结束后重新注册当前列表并恢复策略，避免“软件源”页丢失队列收缩能力。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.registerLiquidGlassContentScrollView()
                self.restoreLiquidGlassMinimizeBehaviorIfNeeded()
            }
        }
        if shouldSelectIndex == tabBarController.sileoSelectedIndex {
            if let splitViewController = viewController as? UISplitViewController {
                if let navController = splitViewController.viewControllers[0] as? UINavigationController {
                    navController.popToRootViewController(animated: true)
                }
            }
        }
        if tabBarController.sileoSelectedIndex == 4 && shouldSelectIndex == 4 {
            if let navController = tabBarController.sileoViewControllers?[4] as? SileoNavigationController,
               let packageList = navController.viewControllers[0] as? PackageListViewController {
                packageList.searchController.searchBar.becomeFirstResponder()
            }
        }
        if tabBarController.sileoSelectedIndex == 3 && shouldSelectIndex == 3 {
            if let navController = tabBarController.sileoViewControllers?[3] as? SileoNavigationController,
               let packageList = navController.viewControllers[0] as? PackageListViewController,
               let collectionView = packageList.collectionView {
                let yVal = -1 * collectionView.adjustedContentInset.top
                collectionView.setContentOffset(CGPoint(x: 0, y: yVal), animated: true)
            }
        }
        if tabBarController.sileoSelectedIndex ==  2 && !fuckedUpSources {
            let sourcesNaVC = (tabBarController.sileoViewControllers?[2] as? SileoNavigationController) ??
                (tabBarController.sileoViewControllers?[2] as? UISplitViewController)?.viewControllers[0] as? SileoNavigationController
            if let sourcesNaVC {
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
        presentPopup(animated: true, completion: completion)
    }

    private func presentPopup(animated: Bool, completion: (() -> Void)?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.presentPopup(animated: animated, completion: completion)
            }
            return
        }

        if usesSystemQueueSheetPresentation, (isQueueSheetVisible || isPresentingQueueSheet) {
            completion?()
            return
        }

        if #available(iOS 26.0, *), usesLiquidGlassQueueAccessory {
            guard let downloadsController,
                  !popupIsPresented else {
                if popupIsPresented {
                    updateLiquidGlassQueueBar()
                }
                completion?()
                return
            }

            popupIsPresented = true
            updateLiquidGlassTabBarMinimizeBehavior()
            if let queueVC = downloadsController.viewControllers.first as? DownloadsTableViewController {
                queueVC.usesSystemQueueSheetPresentation = false
            }
            presentLiquidGlassQueueBar()
            updateSileoColors()
            completion?()
            return
        }

        presentLegacyPopup(animated: animated, completion: completion)
    }

    private func presentLegacyPopup(animated: Bool, completion: (() -> Void)?) {
        if let completion {
            legacyPopupPresentationCompletions.append(completion)
        }
        shouldPresentLegacyPopupBar = true

        switch legacyPopupBarState {
        case .hidden:
            beginLegacyPopupPresentation(animated: animated)
        case .presenting, .dismissing:
            break
        case .presented:
            finishLegacyPopupPresentationRequests()
        }
    }

    private func beginLegacyPopupPresentation(animated: Bool = true) {
        guard case .hidden = legacyPopupBarState,
              let downloadsController else {
            return
        }

        // UIKit 的布局回调可能同步重入 updatePopup；先进入 presenting，禁止重复展示。
        legacyPopupBarState = .presenting
        popupIsPresented = true
        updateLiquidGlassTabBarMinimizeBehavior()
        if let queueVC = downloadsController.viewControllers.first as? DownloadsTableViewController {
            queueVC.usesSystemQueueSheetPresentation = false
        }

        self.popupBar.tabBarHeight = self.tabBar.frame.height
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.popupBar.isInlineWithTabBar = true
            self.popupBar.tabBarHeight = legacyInlineQueueHeight
        }
        self.popupBar.progressViewStyle = .bottom
        self.popupInteractionStyle = queueCollapsedInteractionStyle
        self.presentPopupBar(withContentViewController: downloadsController, animated: animated) { [weak self] in
            self?.completeLegacyPopupPresentation()
        }
        self.configurePopupTapIfNeeded()
        self.updateSileoColors()
    }

    private func completeLegacyPopupPresentation() {
        guard case .presenting = legacyPopupBarState else {
            return
        }

        legacyPopupBarState = .presented
        legacyPopupContentState = .closed
        updateLegacyQueueBarLayout()
        if !shouldPresentLegacyPopupBar {
            beginLegacyPopupDismissal()
        }
        finishLegacyPopupPresentationRequests()
        processLegacyPopupContentRequest()
    }
    
    func dismissPopup() {
        dismissPopup(completion: nil)
    }
    
    func dismissPopup(completion: (() -> Void)?) {
        dismissPopup(animated: true, completion: completion)
    }

    private func dismissPopup(animated: Bool, completion: (() -> Void)?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.dismissPopup(animated: animated, completion: completion)
            }
            return
        }

        if #available(iOS 26.0, *), usesLiquidGlassQueueAccessory {
            guard popupIsPresented else {
                completion?()
                return
            }

            popupIsPresented = false
            updateLiquidGlassTabBarMinimizeBehavior()
            removeLiquidGlassQueueBar()
            completion?()
            return
        }

        dismissLegacyPopup(animated: animated, completion: completion)
    }

    private func dismissLegacyPopup(animated: Bool, completion: (() -> Void)?) {
        if let completion {
            legacyPopupDismissalCompletions.append(completion)
        }
        shouldPresentLegacyPopupBar = false

        switch legacyPopupBarState {
        case .presented:
            beginLegacyPopupDismissal(animated: animated)
        case .presenting, .dismissing:
            break
        case .hidden:
            popupIsPresented = false
            finishLegacyPopupDismissalRequests()
        }
    }

    private func beginLegacyPopupDismissal(animated: Bool = true) {
        guard case .presented = legacyPopupBarState else {
            return
        }

        legacyPopupBarState = .dismissing
        popupIsPresented = false
        updateLiquidGlassTabBarMinimizeBehavior()
        if #available(iOS 26.0, *) {
            removePopupTapCatcher()
        }
        self.dismissPopupBar(animated: animated) { [weak self] in
            self?.completeLegacyPopupDismissal()
        }
    }

    private func completeLegacyPopupDismissal() {
        guard case .dismissing = legacyPopupBarState else {
            return
        }

        legacyPopupBarState = .hidden
        legacyPopupContentState = .closed
        shouldOpenLegacyPopupContent = nil
        finishLegacyPopupOpenRequests()
        finishLegacyPopupCloseRequests()
        if shouldPresentLegacyPopupBar {
            beginLegacyPopupPresentation()
        }
        finishLegacyPopupDismissalRequests()
    }
    
    func presentPopupController() {
        self.presentPopupController(completion: nil)
    }
    
    func presentPopupController(completion: (() -> Void)?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.presentPopupController(completion: completion)
            }
            return
        }

        if usesSystemQueueSheetPresentation {
            presentSystemQueueSheet(completion: completion)
            return
        }

        switch legacyPopupBarState {
        case .presenting, .presented:
            break
        case .dismissing where shouldPresentLegacyPopupBar:
            break
        case .hidden, .dismissing:
            completion?()
            return
        }

        if let completion {
            legacyPopupOpenCompletions.append(completion)
        }
        shouldOpenLegacyPopupContent = true
        processLegacyPopupContentRequest()
    }
    
    func dismissPopupController() {
        self.dismissPopupController(completion: nil)
    }
    
    func dismissPopupController(completion: (() -> Void)?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.dismissPopupController(completion: completion)
            }
            return
        }

        if usesSystemQueueSheetPresentation,
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

        if #available(iOS 26.0, *), usesLiquidGlassQueueAccessory, popupIsPresented {
            dismissPopup(completion: completion)
            return
        }

        guard popupIsPresented else {
            completion?()
            return
        }

        if let completion {
            legacyPopupCloseCompletions.append(completion)
        }
        shouldOpenLegacyPopupContent = false
        processLegacyPopupContentRequest()
    }

    private func processLegacyPopupContentRequest() {
        guard case .presented = legacyPopupBarState,
              let shouldOpenLegacyPopupContent else {
            return
        }

        switch (shouldOpenLegacyPopupContent, legacyPopupContentState) {
        case (true, .closed):
            legacyPopupContentState = .opening
            popupInteractionStyle = preferredPopupInteractionStyle
            openPopup(animated: true) { [weak self] in
                self?.legacyPopupContentTransitionCompleted(isOpen: true)
            }
        case (false, .open):
            legacyPopupContentState = .closing
            closePopup(animated: true) { [weak self] in
                self?.legacyPopupContentTransitionCompleted(isOpen: false)
            }
        case (true, .open):
            self.shouldOpenLegacyPopupContent = nil
            finishLegacyPopupOpenRequests()
        case (false, .closed):
            self.shouldOpenLegacyPopupContent = nil
            finishLegacyPopupCloseRequests()
        case (true, .opening), (true, .closing), (false, .opening), (false, .closing):
            break
        }
    }

    private func legacyPopupContentTransitionCompleted(isOpen: Bool) {
        legacyPopupContentState = isOpen ? .open : .closed
        if isOpen {
            finishLegacyPopupOpenRequests()
            downloadsController?.view.setNeedsLayout()
            downloadsController?.view.layoutIfNeeded()
        } else {
            updateLegacyQueueBarLayout()
            finishLegacyPopupCloseRequests()
        }
        if shouldOpenLegacyPopupContent == isOpen {
            shouldOpenLegacyPopupContent = nil
        }
        processLegacyPopupContentRequest()
    }

    private func finishLegacyPopupPresentationRequests() {
        let completions = legacyPopupPresentationCompletions
        legacyPopupPresentationCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func finishLegacyPopupDismissalRequests() {
        let completions = legacyPopupDismissalCompletions
        legacyPopupDismissalCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func finishLegacyPopupOpenRequests() {
        let completions = legacyPopupOpenCompletions
        legacyPopupOpenCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func finishLegacyPopupCloseRequests() {
        let completions = legacyPopupCloseCompletions
        legacyPopupCloseCompletions.removeAll()
        completions.forEach { $0() }
    }
    
    func updatePopup() {
        updatePopup(completion: nil)
    }
    
    func updatePopup(completion: (() -> Void)? = nil, bypass: Bool = false) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.updatePopup(completion: completion, bypass: bypass)
            }
            return
        }

        if isQueueSheetVisible || isPresentingQueueSheet {
            completion?()
            return
        }

        func hideRegardless() {
            if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
                // iPadOS 26 不再常驻一个“0 个软件包”的旧 popup bar。
                self.dismissPopup(completion: completion)
                return
            }
            if UIDevice.current.userInterfaceIdiom == .pad && self.view.frame.width >= 768 {
                downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), 0)
                // 旧系统沿用 LNPopup 的完整过渡；状态机负责合并布局期间的重复请求。
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
        if #available(iOS 26.0, *) {
            // 搜索收缩也会改变环境特征，此时重设外观会打断正在过渡的图标绘制。
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                updateSileoColors()
            }
        } else {
            updateSileoColors()
        }
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

        (tabBar as? TabBar)?.trackSourceRefreshScrollTransition()
        restoreLiquidGlassMinimizeBehaviorIfNeeded()

        // 当前页面可能是导航栈里的详情页，把实际滚动视图直接交给顶部导航容器。
        if !isPackagesTabScrollView(scrollView) {
            setContentScrollView(scrollView, for: .top)
            sileoSelectedViewController?.setContentScrollView(scrollView, for: .top)
        }
        if isSourcesScrollView(scrollView) {
            driveSourcesQueueMinimizeIfNeeded(from: scrollView)
        } else {
            setContentScrollView(scrollView, for: .bottom)
            sileoSelectedViewController?.setContentScrollView(scrollView, for: .bottom)
        }
    }

    func prepareLiquidGlassScroll(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *),
              usesFloatingQueueCardOnPhone,
              popupIsPresented,
              isSourcesScrollView(scrollView) else {
            return
        }

        let topOffset = -scrollView.adjustedContentInset.top
        guard scrollView.contentOffset.y > topOffset + 0.5 else {
            registerSourcesScrollView(scrollView)
            return
        }

        // 新一轮拖动开始前锁住已经完成的系统紧凑态，避免反向滑动立刻触发系统展开。
        if currentLiquidGlassMorphTarget() == 2 {
            sourcesQueueIsMinimized = true
            registerSourcesQueueTrackingScrollView()
        } else {
            sourcesQueueIsMinimized = false
            registerSourcesScrollView(scrollView)
        }
    }

    @available(iOS 26.0, *)
    private func isPackagesTabScrollView(_ scrollView: UIScrollView) -> Bool {
        guard sileoSelectedIndex == 3 else {
            return false
        }
        if let nav = sileoSelectedViewController as? UINavigationController,
           let packageList = nav.topViewController as? PackageListViewController {
            return packageList.collectionView === scrollView
        }
        if let packageList = sileoSelectedViewController as? PackageListViewController {
            return packageList.collectionView === scrollView
        }
        return false
    }

    @available(iOS 26.0, *)
    private func isSourcesScrollView(_ scrollView: UIScrollView) -> Bool {
        guard let sileoSelectedViewController,
              let sourcesViewController = sourcesViewController(in: sileoSelectedViewController) else {
            return false
        }
        return sourcesViewController.tableView === scrollView
    }

    @available(iOS 26.0, *)
    private func sourcesViewController(in viewController: UIViewController) -> SourcesViewController? {
        if let sourcesViewController = viewController as? SourcesViewController {
            return sourcesViewController
        }
        if let navigationController = viewController as? UINavigationController,
           let topViewController = navigationController.topViewController {
            return sourcesViewController(in: topViewController)
        }
        if let splitViewController = viewController as? UISplitViewController {
            for childViewController in splitViewController.viewControllers {
                if let sourcesViewController = sourcesViewController(in: childViewController) {
                    return sourcesViewController
                }
            }
        }
        return nil
    }

    @available(iOS 26.0, *)
    private func driveSourcesQueueMinimizeIfNeeded(from scrollView: UIScrollView) {
        guard isSourcesScrollView(scrollView) else {
            return
        }

        let topOffset = -scrollView.adjustedContentInset.top
        if scrollView.contentOffset.y <= topOffset + 0.5 {
            // 离开顶部后的反向滚动不能展开队列，只有内容真正回到顶部才恢复完整标签栏。
            if currentLiquidGlassMorphTarget() == 2 {
                sourcesQueueIsMinimized = true
                setLiquidGlassQueueMinimized(false)
            } else {
                sourcesQueueIsMinimized = false
            }
            registerSourcesScrollView(scrollView)
            return
        }

        if currentLiquidGlassMorphTarget() == 2 {
            sourcesQueueIsMinimized = true
            registerSourcesQueueTrackingScrollView()
            return
        }

        // 第一次向内容下方滚动时让 UIKit 自己完成完整的 accessory/tab morph；
        // 这样系统会正确生成“当前标签 + 队列 + 搜索”的三段紧凑布局。
        sourcesQueueIsMinimized = false
        registerSourcesScrollView(scrollView)
    }

    @available(iOS 26.0, *)
    @discardableResult
    private func setLiquidGlassQueueMinimized(_ minimized: Bool) -> Bool {
        guard sourcesQueueIsMinimized != minimized,
              popupIsPresented,
              let visualProviderIvar = class_getInstanceVariable(UITabBar.self, "_visualProvider"),
              let visualProvider = object_getIvar(tabBar, visualProviderIvar) as? NSObject,
              NSStringFromClass(type(of: visualProvider)).contains("_UITabBarVisualProvider_Floating") else {
            return sourcesQueueIsMinimized == minimized
        }

        // UITabBar._setMinimized: 在 iOS 26 内部只允许 Photos 调用，会触发断言。
        // 浮动 visual provider 才是系统滚动交互最终调用的原生 morph 入口。
        let selector = NSSelectorFromString("setMinimized:")
        guard visualProvider.responds(to: selector) else {
            return false
        }

        typealias SetMinimizedImplementation = @convention(c) (AnyObject, Selector, Bool) -> Void
        let implementation = visualProvider.method(for: selector)
        let setMinimized = unsafeBitCast(implementation, to: SetMinimizedImplementation.self)
        setMinimized(visualProvider, selector, minimized)
        sourcesQueueIsMinimized = minimized
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let sourcesRootController = self.sileoViewControllers?[safe: 2] else {
                return
            }
            self.sourcesViewController(in: sourcesRootController)?.layoutSourceRefreshIndicatorIfNeeded()
        }
        return true
    }

    @available(iOS 26.0, *)
    private func currentLiquidGlassMorphTarget() -> Int? {
        guard let visualProviderIvar = class_getInstanceVariable(UITabBar.self, "_visualProvider"),
              let visualProvider = object_getIvar(tabBar, visualProviderIvar) as? NSObject,
              NSStringFromClass(type(of: visualProvider)).contains("_UITabBarVisualProvider_Floating") else {
            return nil
        }
        return (visualProvider.value(forKey: "_currentMorphTarget") as? NSNumber)?.intValue
    }

    @available(iOS 26.0, *)
    private func registerSourcesScrollView(_ scrollView: UIScrollView) {
        setContentScrollView(scrollView, for: .bottom)
        sileoSelectedViewController?.setContentScrollView(scrollView, for: .bottom)
    }

    @available(iOS 26.0, *)
    private func registerSourcesQueueTrackingScrollView() {
        guard let sileoSelectedViewController else {
            return
        }

        let trackingScrollView: UIScrollView
        if let existingScrollView = sourcesQueueTrackingScrollView {
            trackingScrollView = existingScrollView
        } else {
            let createdScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            createdScrollView.isUserInteractionEnabled = false
            createdScrollView.alpha = 0.001
            createdScrollView.contentSize = CGSize(width: 1, height: 2)
            createdScrollView.isAccessibilityElement = false
            createdScrollView.accessibilityElementsHidden = true
            createdScrollView.accessibilityIdentifier = "Sileo.SourcesQueueTrackingScrollView"
            sourcesQueueTrackingScrollView = createdScrollView
            trackingScrollView = createdScrollView
        }

        if trackingScrollView.superview !== sileoSelectedViewController.view {
            trackingScrollView.removeFromSuperview()
            sileoSelectedViewController.view.insertSubview(trackingScrollView, at: 0)
        }
        setContentScrollView(trackingScrollView, for: .bottom)
        sileoSelectedViewController.setContentScrollView(trackingScrollView, for: .bottom)
    }

    @available(iOS 26.0, *)
    private func desiredLiquidGlassMinimizeBehavior() -> UITabBarController.MinimizeBehavior {
        // accessory 在清空队列时尚未移除，不能用它判断队列是否仍然存在。
        guard popupIsPresented else {
            return .never
        }
        return .onScrollDown
    }

    @available(iOS 26.0, *)
    private func restoreLiquidGlassMinimizeBehaviorIfNeeded() {
        guard usesFloatingQueueCardOnPhone,
              !isQueueSheetVisible,
              !isPresentingQueueSheet else {
            return
        }
        let desiredBehavior = desiredLiquidGlassMinimizeBehavior()
        if tabBarMinimizeBehavior != desiredBehavior {
            tabBarMinimizeBehavior = desiredBehavior
        }
    }

    @available(iOS 26.0, *)
    private func registerLiquidGlassContentScrollView() {
        guard let sileoSelectedViewController,
              let scrollView = liquidGlassContentScrollView(in: sileoSelectedViewController) else {
            return
        }

        if !isPackagesTabScrollView(scrollView) {
            setContentScrollView(scrollView, for: .top)
            sileoSelectedViewController.setContentScrollView(scrollView, for: .top)
        }
        if isSourcesScrollView(scrollView) {
            if popupIsPresented && currentLiquidGlassMorphTarget() == 2 {
                sourcesQueueIsMinimized = true
                registerSourcesQueueTrackingScrollView()
            } else {
                sourcesQueueIsMinimized = false
                registerSourcesScrollView(scrollView)
            }
        } else {
            setContentScrollView(scrollView, for: .bottom)
            sileoSelectedViewController.setContentScrollView(scrollView, for: .bottom)
        }
        restoreLiquidGlassMinimizeBehaviorIfNeeded()
    }

    @available(iOS 26.0, *)
    private func liquidGlassContentScrollView(in viewController: UIViewController) -> UIScrollView? {
        if let sourcesVC = viewController as? SourcesViewController, let tv = sourcesVC.tableView {
            return tv
        }
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
        guard usesSystemQueueSheetPresentation,
              popupIsPresented,
              !isQueueSheetVisible,
              !isPresentingQueueSheet
        else {
            return
        }
        presentPopupController()
    }

    private func queueSheetPresenter() -> UIViewController? {
        // 设置及其插件详情位于独立的模态导航栈，队列必须从最上层页面展示。
        var presenter: UIViewController = self
        while let presentedController = presenter.presentedViewController {
            guard presentedController !== downloadsController else {
                return nil
            }
            presenter = presentedController
        }

        guard presenter.viewIfLoaded?.window != nil,
              !presenter.isBeingPresented,
              !presenter.isBeingDismissed,
              presenter.transitionCoordinator == nil,
              !(presenter is UIAlertController) else {
            return nil
        }
        return presenter
    }

    private func presentSystemQueueSheet(completion: (() -> Void)?) {
        guard usesSystemQueueSheetPresentation,
              popupIsPresented,
              !isPresentingQueueSheet,
              !isQueueSheetVisible,
              downloadsController != nil,
              queueSheetPresenter() != nil,
              viewIfLoaded?.window != nil
        else {
            completion?()
            return
        }

        isPresentingQueueSheet = true
        if #available(iOS 26.0, *), usesLiquidGlassQueueAccessory {
            // 保留 bottomAccessory，让系统在 sheet 关闭后恢复原来的展开/紧凑位置。
            presentQueueSheet(completion: completion)
        } else {
            dismissPopup(animated: false) { [weak self] in
                self?.presentQueueSheet(completion: completion)
            }
        }
    }

    private func presentQueueSheet(completion: (() -> Void)?) {
        // 移除旧队列条后重新确认展示层级；失败时恢复底部条，不能留下“正在展示”。
        guard let downloadsController = downloadsController,
              let presenter = queueSheetPresenter() else {
            isPresentingQueueSheet = false
            updatePopup()
            completion?()
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

        downloadsController.presentationController?.delegate = self
        var didFinishPresentation = false
        func finishPresentation() {
            guard !didFinishPresentation else { return }
            didFinishPresentation = true
            self.isQueueSheetVisible = downloadsController.presentingViewController != nil
            self.isPresentingQueueSheet = false
            if !self.isQueueSheetVisible {
                self.updatePopup()
            }
            completion?()
        }

        presenter.present(downloadsController, animated: true) {
            downloadsController.presentationController?.delegate = self
            finishPresentation()
        }
        // UIKit 拒绝展示时不会执行完成回调，下一轮主队列检查是否建立了展示关系。
        DispatchQueue.main.async {
            if downloadsController.presentingViewController == nil && !downloadsController.isBeingPresented {
                finishPresentation()
            }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard usesSystemQueueSheetPresentation,
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
        let tintColor = UIColor.tintColor
        view.tintColor = tintColor
        tabBar.tintColor = tintColor
        tabBar.unselectedItemTintColor = .label
        refreshTabBarAppearance(tintColor: tintColor)

        self.popupBar.tintColor = UINavigationBar.appearance().tintColor
        if #available(iOS 26.0, *), usesLiquidGlassQueueAccessory {
            updateLiquidGlassQueueBar()
        } else if #available(iOS 26.0, *) {
            applyLiquidGlassPopupAppearance()
        }
        if self.responds(to: NSSelectorFromString("setNeedsPopupBarAppearanceUpdate")) {
            _ = self.perform(NSSelectorFromString("setNeedsPopupBarAppearanceUpdate"))
        }
    }

    private func refreshTabBarAppearance(tintColor: UIColor) {
        guard #available(iOS 13.0, *) else {
            return
        }

        func appearanceByUpdatingSelectedColor(_ source: UITabBarAppearance) -> UITabBarAppearance {
            let appearance = source.copy() as! UITabBarAppearance
            let itemAppearances = [
                appearance.stackedLayoutAppearance,
                appearance.inlineLayoutAppearance,
                appearance.compactInlineLayoutAppearance
            ]
            for itemAppearance in itemAppearances {
                var titleAttributes = itemAppearance.selected.titleTextAttributes
                titleAttributes[.foregroundColor] = tintColor
                itemAppearance.selected.titleTextAttributes = titleAttributes
                itemAppearance.selected.iconColor = tintColor
            }
            return appearance
        }

        let standardAppearance = appearanceByUpdatingSelectedColor(tabBar.standardAppearance)
        tabBar.standardAppearance = standardAppearance
        if #available(iOS 15.0, *) {
            let source = tabBar.scrollEdgeAppearance ?? standardAppearance
            tabBar.scrollEdgeAppearance = appearanceByUpdatingSelectedColor(source)
        }

        for item in tabBar.items ?? [] {
            var titleAttributes = item.titleTextAttributes(for: .selected) ?? [:]
            titleAttributes[.foregroundColor] = tintColor
            item.setTitleTextAttributes(titleAttributes, for: .selected)
        }

        tabBar.setNeedsLayout()
    }

    private func updateLiquidGlassTabBarMinimizeBehavior() {
        guard #available(iOS 26.0, *), usesFloatingQueueCardOnPhone else {
            return
        }
        tabBarMinimizeBehavior = desiredLiquidGlassMinimizeBehavior()
        if !popupIsPresented {
            sourcesQueueIsMinimized = false
        }
    }

    private var legacyInlineQueueHeight: CGFloat {
        let displayScale = max(view.window?.screen.scale ?? traitCollection.displayScale, 1)
        // 系统标签栏的顶线位于 bounds 上方一像素，旧库的顶线则位于内部 y = 0.5pt。
        // 两段偏移都要补偿，才能让静态顶线对齐，而非依赖鼠标悬停时的放大效果。
        let popupShadowOffset: CGFloat = 0.5
        return tabBar.bounds.height + popupShadowOffset + 1 / displayScale
    }

    private func updateLegacyQueueBarLayout() {
        guard #unavailable(iOS 26.0),
              UIDevice.current.userInterfaceIdiom == .pad,
              case .presented = legacyPopupBarState,
              case .closed = legacyPopupContentState,
              popupBar.isInlineWithTabBar,
              tabBar.bounds.height > 0,
              let popupSuperview = popupBar.superview else { return }

        let panState = popupContentView.popupInteractionGestureRecognizer.state
        guard panState != .began, panState != .changed else { return }

        let height = legacyInlineQueueHeight
        popupBar.tabBarHeight = height
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: popupSuperview)
        // 宽窗口与菜单并排，窄窗口沿用旧库的上方停靠；每次都按实际标签栏位置重新对齐。
        let bottom = insetsForBottomDockingView.left > 0 ? tabBarFrame.maxY : tabBarFrame.minY
        let centerY = bottom - height / 2
        if abs(height - popupBar.bounds.height) > 0.001 || abs(centerY - popupBar.center.y) > 0.001 {
            // 使用 bounds 和 center，避免鼠标悬停缩放影响 frame；保留库内文字排版。
            popupBar.bounds.size.height = height
            popupBar.center.y = centerY
            popupBar.setNeedsLayout()
        }
        popupBar.layoutIfNeeded()

        guard let contentView = popupBar.toolbar.superview else { return }
        let separator: UIView
        if let existingSeparator = legacyQueueSeparatorExtension {
            separator = existingSeparator
        } else {
            separator = UIView()
            separator.isUserInteractionEnabled = false
            separator.backgroundColor = UIColor(white: 169 / 255, alpha: 1)
            legacyQueueSeparatorExtension = separator
        }
        if separator.superview !== contentView {
            contentView.addSubview(separator)
        }
        // 旧库的分隔线只画到内部 toolbar 底部，补齐剩余高度，沿用原线的颜色和横坐标。
        let screen = popupBar.window?.screen
        let displayScale = max(screen?.nativeScale ?? traitCollection.displayScale, 1)
        let separatorTop = min(popupBar.toolbar.bounds.height, contentView.bounds.height)
        separator.frame = CGRect(x: 0.5, y: separatorTop, width: 1 / displayScale,
                                 height: max(0, contentView.bounds.height - separatorTop))
        separator.isHidden = insetsForBottomDockingView.left == 0
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (tabBar as? TabBar)?.attachDecorations(to: view)
        
        self.tabBar.itemPositioning = .centered
        if #available(iOS 26.0, *), usesFloatingQueueCardOnPhone {
            // accessory 的首次布局可能会重建标签栏，布局完成后再次保持当前策略。
            restoreLiquidGlassMinimizeBehaviorIfNeeded()
            if let sourcesRootController = sileoViewControllers?[safe: 2] {
                sourcesViewController(in: sourcesRootController)?.layoutSourceRefreshIndicatorIfNeeded()
            }
        } else if usesFloatingQueueCardOnPhone {
            configurePopupTapIfNeeded()
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.updatePopup()
            updateLegacyQueueBarLayout()
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
        if usesFloatingQueueCardOnPhone {
            restoreLiquidGlassMinimizeBehaviorIfNeeded()
        }
    }

    @available(iOS 26.0, *)
    private func updateLiquidGlassQueueBar() {
        liquidGlassQueueBar?.update(title: downloadsController?.popupItem.title,
                                    subtitle: downloadsController?.popupItem.subtitle)
    }

    @available(iOS 26.0, *)
    private func removeLiquidGlassQueueBar() {
        setBottomAccessory(nil, animated: false)
        sourcesQueueIsMinimized = false
        liquidGlassQueueBar?.isHidden = true
        liquidGlassQueueBar?.removeFromSuperview()

        // 清除维持队列紧凑态的占位滚动视图，让真实列表重新接管滚动。
        if let trackingScrollView = sourcesQueueTrackingScrollView {
            for controller in [self] + (sileoViewControllers ?? [])
            where controller.contentScrollView(for: .bottom) === trackingScrollView {
                controller.setContentScrollView(nil, for: .bottom)
            }
            trackingScrollView.removeFromSuperview()
            sourcesQueueTrackingScrollView = nil
        }
        if usesFloatingQueueCardOnPhone {
            registerLiquidGlassContentScrollView()
            // 移除 accessory 可能重建标签栏，完成后再次确保空队列禁止收缩。
            updateLiquidGlassTabBarMinimizeBehavior()
        }
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
        self.presentSileoAlert(alertController)
    }
}

extension TabBarController: LNPopupPresentationDelegate {
    func popupPresentationControllerWillOpenPopup(_ popupPresentationController: UIViewController, animated: Bool) {
        legacyPopupContentState = .opening
    }

    func popupPresentationControllerDidOpenPopup(_ popupPresentationController: UIViewController, animated: Bool) {
        legacyPopupContentTransitionCompleted(isOpen: true)
    }

    func popupPresentationControllerWillClosePopup(_ popupPresentationController: UIViewController, animated: Bool) {
        legacyPopupContentState = .closing
    }

    func popupPresentationControllerDidClosePopup(_ popupPresentationController: UIViewController, animated: Bool) {
        legacyPopupContentTransitionCompleted(isOpen: false)
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

    private var padWidthConstraint: NSLayoutConstraint?

    func calculatedPadWidth() -> CGFloat {
        let hostWidth: CGFloat
        if let parentWidth = TabBarController.singleton?.view.bounds.width, parentWidth > 100 {
            hostWidth = parentWidth
        } else if let windowWidth = window?.bounds.width, windowWidth > 100 {
            hostWidth = windowWidth
        } else {
            hostWidth = UIScreen.main.bounds.width
        }
        return max(320, hostWidth - 32)
    }

    func updatePadWidthConstraintIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let targetWidth = calculatedPadWidth()
        if let constraint = padWidthConstraint {
            if constraint.constant != targetWidth {
                constraint.constant = targetWidth
                invalidateIntrinsicContentSize()
            }
        } else {
            translatesAutoresizingMaskIntoConstraints = false
            let constraint = widthAnchor.constraint(equalToConstant: targetWidth)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            padWidthConstraint = constraint
            invalidateIntrinsicContentSize()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if UIDevice.current.userInterfaceIdiom == .pad {
            updatePadWidthConstraintIfNeeded()
        }
    }

    override var intrinsicContentSize: CGSize {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return CGSize(width: calculatedPadWidth(), height: 64)
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: 64)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let width = size.width > 100 ? size.width : calculatedPadWidth()
            return CGSize(width: width, height: 64)
        }
        return super.sizeThatFits(size)
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
        if UIDevice.current.userInterfaceIdiom == .pad {
            updatePadWidthConstraintIfNeeded()
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if UIDevice.current.userInterfaceIdiom == .pad {
            updatePadWidthConstraintIfNeeded()
        }
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

// 新标签 API 不维护旧的数组与选择属性，业务入口统一通过这些访问器定位页面。
extension UITabBarController {
    fileprivate func prepareSileoTabSelection(_ controller: UIViewController?) {
        guard let index = sileoViewControllers?.firstIndex(where: { $0 === controller }) else { return }
        (tabBar as? TabBar)?.prepareForTabSelection(index: index, item: controller?.tabBarItem,
                                                  previousIndex: sileoSelectedIndex,
                                                  previousItem: sileoSelectedViewController?.tabBarItem)
    }

    var sileoViewControllers: [UIViewController]? {
        if #available(iOS 18.0, *), !tabs.isEmpty {
            return tabs.compactMap { $0.viewController }
        }
        return viewControllers
    }

    var sileoSelectedViewController: UIViewController? {
        get {
            if #available(iOS 18.0, *), !tabs.isEmpty {
                return selectedTab?.viewController
            }
            return selectedViewController
        }
        set {
            prepareSileoTabSelection(newValue)
            if #available(iOS 18.0, *), !tabs.isEmpty {
                selectedTab = tabs.first { $0.viewController === newValue }
            } else {
                selectedViewController = newValue
            }
        }
    }

    var sileoSelectedIndex: Int {
        get {
            if #available(iOS 18.0, *), !tabs.isEmpty {
                return tabs.firstIndex { $0 === selectedTab } ?? NSNotFound
            }
            return selectedIndex
        }
        set {
            if #available(iOS 18.0, *), !tabs.isEmpty {
                guard tabs.indices.contains(newValue) else { return }
                prepareSileoTabSelection(tabs[newValue].viewController)
                selectedTab = tabs[newValue]
            } else {
                if let controller = viewControllers?[safe: newValue] {
                    prepareSileoTabSelection(controller)
                }
                selectedIndex = newValue
            }
        }
    }
}

extension UIViewController {
    func setSileoTabBadgeValue(_ value: String?) {
        tabBarItem.badgeValue = value
        if #available(iOS 18.0, *) {
            tab?.badgeValue = value
        }
    }
}
