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
    private enum SileoTabIdentifier {
        static let featured = "sileo.tab.featured"
        static let news = "sileo.tab.news"
        static let sources = "sileo.tab.sources"
        static let packages = "sileo.tab.packages"

        static func identifier(for index: Int) -> String {
            switch index {
            case 0: return featured
            case 1: return news
            case 2: return sources
            case 3: return packages
            default: return "sileo.tab.\(index)"
            }
        }
    }

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
    private let nativeRefreshBadge = NativeRefreshBadge()
    private var nativeBadgePortalLift: NativeBadgePortalLift?
    private var anchoredBadges: AnchoredBadgeRenderer?
    private var badgeTickTarget: ModernBadgeDisplayTick?
    private var badgeDisplayLink: CADisplayLink?
    private var badgeDisplayLinkUsesHighRate = false
    private var isModernTabBarVisible = false
    private var isSourcesRefreshing = false
    private var packageBadgeValue: String?
    private var packageBadgeColor: UIColor?
    private var lastNonSearchTabIdentifier: String?
    private var isModernPadSearchActive = false
    private var transientPadSelectedTabTitle: String?
    private var transientPadSelectionResetWorkItem: DispatchWorkItem?
    private var suspendedPadTabBarPointerInteractions: [ObjectIdentifier: UIPointerInteraction] = [:]
    private var padPointerRestoreWorkItem: DispatchWorkItem?
    private let modernPadScrollStates = NSMapTable<UIScrollView, ModernPadScrollState>.weakToStrongObjects()
    private struct CompactBadgeSyncAttempt: Equatable {
        let buttonID: ObjectIdentifier
        let title: String
        let expected: String?
        let observed: String?
    }
    private var lastCompactBadgeSyncAttempt: CompactBadgeSyncAttempt?

    var isQueuePresentationVisible: Bool {
        popupIsPresented ||
        isPresentingQueueSheet ||
        isQueueSheetEffectivelyVisible ||
        presentedViewController === downloadsController
    }

    private var isQueueSheetEffectivelyVisible: Bool {
        if isQueueSheetVisible && downloadsController?.presentingViewController == nil {
            isQueueSheetVisible = false
        }
        return isQueueSheetVisible
    }
    
    private var preferredPopupInteractionStyle: LNPopupInteractionStyle {
        UIDevice.current.userInterfaceIdiom == .phone ? .snap : .drag
    }

    private var usesFloatingQueueCardOnPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var usesModernPadBottomTabMenu: Bool {
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            return true
        }
        return false
    }

    private var usesModernTabMenu: Bool {
        if #available(iOS 26.0, *) {
            let idiom = UIDevice.current.userInterfaceIdiom
            return idiom == .phone || idiom == .pad
        }
        return false
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

    deinit {
        transientPadSelectionResetWorkItem?.cancel()
        padPointerRestoreWorkItem?.cancel()
        badgeDisplayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        delegate = self
        TabBarController.singleton = self
        if usesModernTabMenu, let sileoTabBar = tabBar as? TabBar {
            if usesModernPadBottomTabMenu {
                sileoTabBar.modernPadWidthRatio = 0.5
            }
            if #available(iOS 27.0, *) {
                nativeBadgePortalLift = NativeBadgePortalLift()
            }
            sileoTabBar.onLayoutSubviews = { [weak self] in
                guard let self else { return }
                if #available(iOS 26.0, *), self.usesModernPadBottomTabMenu {
                    self.ensureModernPadHostedSearchOrderIfNeeded()
                    self.alignModernPadHostedSearchBarIfNeeded()
                    if self.transientPadSelectedTabTitle != nil {
                        self.syncModernPadSelectedTabVisualsIfNeeded()
                    }
                }
                self.anchoredBadges?.invalidateLayout()
                self.updateModernTabBadges()
            }
            sileoTabBar.onDidMoveToWindow = { [weak self] in
                guard let self else { return }
                if self.tabBar.window == nil {
                    self.stopModernTabBadgeDisplayLink()
                    self.anchoredBadges?.detach()
                    self.nativeBadgePortalLift?.deactivate()
                    if #available(iOS 26.0, *), self.usesModernPadBottomTabMenu {
                        self.restoreModernPadPointerInteractionIfMorphEnded(force: true)
                    }
                } else {
                    self.anchoredBadges?.invalidateLayout()
                    self.updateModernTabBadges()
                    self.updateModernTabBadgeDisplayLink()
                }
            }
            sileoTabBar.onDidAddSubview = { [weak self] subview in
                guard let self else { return }
                if #available(iOS 26.0, *) {
                    if self.usesModernPadBottomTabMenu {
                        self.ensureModernPadHostedSearchOrderIfNeeded()
                    }
                    let className = NSStringFromClass(type(of: subview))
                    if className.contains("Reparenting") || className.contains("MagicMorph") {
                        if self.usesModernPadBottomTabMenu {
                            self.suspendModernPadPointerInteractionForMorphIfNeeded()
                        }
                    }
                    if className.contains("PlatterView") || className.contains("Reparenting") {
                        if self.anchoredBadges == nil {
                            self.syncCompactPlatterBadgesIfNeeded(allowDuringMorph: true)
                            if self.isSourcesRefreshing {
                                self.nativeRefreshBadge.update(in: self.modernTabBadgeSearchRoot, isRefreshing: true)
                            }
                        }
                        if self.usesModernPadBottomTabMenu, self.transientPadSelectedTabTitle != nil {
                            self.syncModernPadSelectedTabVisualsIfNeeded()
                        }
                    }
                }
                guard let lift = self.nativeBadgePortalLift else { return }
                lift.update(in: self.tabBar)
                if !lift.isActive, NSStringFromClass(type(of: subview)) == "_UIPortalView" {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.nativeBadgePortalLift?.update(in: self.tabBar)
                    }
                }
            }
            sileoTabBar.onWillRemoveSubview = { [weak self] subview in
                guard let self else { return }
                self.nativeBadgePortalLift?.update(in: self.tabBar, excluding: subview)
                if #available(iOS 26.0, *), self.usesModernPadBottomTabMenu {
                    let className = NSStringFromClass(type(of: subview))
                    if className.contains("Reparenting") || className.contains("MagicMorph") {
                        DispatchQueue.main.async { [weak self] in
                            self?.restoreModernPadPointerInteractionIfMorphEnded()
                            self?.alignModernPadHostedSearchBarIfNeeded()
                        }
                    }
                }
            }
        }

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
        if usesModernTabMenu {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleModernBadgeDidEnterBackground),
                                                   name: UIApplication.didEnterBackgroundNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleModernBadgeWillEnterForeground),
                                                   name: UIApplication.willEnterForegroundNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleModernBadgeWillEnterForeground),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
            if usesModernPadBottomTabMenu {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(handleModernPadSearchTextDidEndEditing(_:)),
                                                       name: UITextField.textDidEndEditingNotification,
                                                       object: nil)
            }
        }
        updateSileoColors()
        updateLiquidGlassTabBarMinimizeBehavior()
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if #available(iOS 26.0, *) {
            restoreModernPadTraitsIfNeeded(for: viewControllerToPresent)
        }
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    @available(iOS 26.0, *)
    private var realWindowSceneHorizontalSizeClass: UIUserInterfaceSizeClass {
        let scene = viewIfLoaded?.window?.windowScene
            ?? (UIApplication.shared.delegate as? SileoAppDelegate)?.window?.windowScene
        if let sizeClass = scene?.traitCollection.horizontalSizeClass, sizeClass != .unspecified {
            return sizeClass
        }
        return .regular
    }

    @available(iOS 26.0, *)
    private func setHorizontalSizeClassOverride(_ value: UIUserInterfaceSizeClass, on overrides: inout UITraitOverrides) {
        if overrides.contains(UITraitHorizontalSizeClass.self),
           overrides.horizontalSizeClass == value {
            return
        }
        overrides.horizontalSizeClass = value
    }

    @available(iOS 26.0, *)
    private func setUserInterfaceIdiomOverride(_ value: UIUserInterfaceIdiom, on overrides: inout UITraitOverrides) {
        if overrides.contains(UITraitUserInterfaceIdiom.self),
           overrides.userInterfaceIdiom == value {
            return
        }
        overrides.userInterfaceIdiom = value
    }

    @available(iOS 26.0, *)
    func prepareModernPadBottomTabTraitsIfNeeded(in window: UIWindow?) {
        guard usesModernPadBottomTabMenu else { return }
        if let targetWindow = window ?? viewIfLoaded?.window {
            setHorizontalSizeClassOverride(.compact, on: &targetWindow.traitOverrides)
            setUserInterfaceIdiomOverride(.phone, on: &targetWindow.traitOverrides)
        }
        setHorizontalSizeClassOverride(.compact, on: &traitOverrides)
        setUserInterfaceIdiomOverride(.phone, on: &traitOverrides)
        if mode != .tabBar {
            mode = .tabBar
        }
        syncModernPadContentTabTraits(window: window)
    }

    @available(iOS 26.0, *)
    func syncModernPadContentTabTraits(window: UIWindow? = nil,
                                       targetHorizontalSizeClass: UIUserInterfaceSizeClass? = nil) {
        guard usesModernPadBottomTabMenu else { return }
        let resolvedHorizontal: UIUserInterfaceSizeClass
        if let targetHorizontalSizeClass, targetHorizontalSizeClass != .unspecified {
            resolvedHorizontal = targetHorizontalSizeClass
        } else if let sceneSizeClass = (window?.windowScene ?? viewIfLoaded?.window?.windowScene)?.traitCollection.horizontalSizeClass,
                  sceneSizeClass != .unspecified {
            resolvedHorizontal = sceneSizeClass
        } else {
            resolvedHorizontal = realWindowSceneHorizontalSizeClass
        }

        for controller in sileoViewControllers ?? [] {
            // 搜索标签保持 .compact + .phone 以启用底栏变形搜索框，其余内容标签恢复真实 iPad 尺寸类与 idiom。
            let isSearchTabController = (controller as? UINavigationController)
                .flatMap { $0.viewControllers.first as? PackageListViewController }?
                .showSearchField == true
            if isSearchTabController {
                controller.traitOverrides.remove(UITraitHorizontalSizeClass.self)
                controller.traitOverrides.remove(UITraitUserInterfaceIdiom.self)
            } else {
                setUserInterfaceIdiomOverride(.pad, on: &controller.traitOverrides)
                setHorizontalSizeClassOverride(resolvedHorizontal, on: &controller.traitOverrides)
            }
        }

        var presented = presentedViewController
        while let vc = presented {
            if !(vc is UISearchController) {
                setUserInterfaceIdiomOverride(.pad, on: &vc.traitOverrides)
                setHorizontalSizeClassOverride(resolvedHorizontal, on: &vc.traitOverrides)
            }
            presented = vc.presentedViewController
        }
    }

    @available(iOS 26.0, *)
    func restoreModernPadTraitsIfNeeded(for viewController: UIViewController) {
        guard usesModernPadBottomTabMenu, !(viewController is UISearchController) else {
            return
        }
        let resolvedHorizontal = realWindowSceneHorizontalSizeClass
        setUserInterfaceIdiomOverride(.pad, on: &viewController.traitOverrides)
        if resolvedHorizontal != .unspecified {
            setHorizontalSizeClassOverride(resolvedHorizontal, on: &viewController.traitOverrides)
        }
    }

    @available(iOS 26.0, *)
    private var modernSearchTabSearchController: UISearchController? {
        for controller in sileoViewControllers ?? [] {
            if let nav = controller as? UINavigationController,
               let pkgList = nav.viewControllers.first as? PackageListViewController,
               pkgList.showSearchField {
                return pkgList.searchController
            }
        }
        return nil
    }

    @available(iOS 26.0, *)
    private func ensureModernPadFullWidthTabPlatterIfNeeded() {
        // 仅 iPadOS 27 支持通过 hostedElements bit 2 (0x4) 将主托盘撑满底栏宽度；
        // iPadOS 26 上强行置位既不会加宽托盘，还可能在队列+搜索形变结束时触发系统 Accessibility 字典空指针崩溃。
        guard #available(iOS 27.0, *),
              usesModernPadBottomTabMenu,
              let visualProviderIvar = class_getInstanceVariable(UITabBar.self, "_visualProvider"),
              let visualProvider = object_getIvar(tabBar, visualProviderIvar) as? NSObject,
              NSStringFromClass(type(of: visualProvider)).contains("_UITabBarVisualProvider_Floating") else {
            return
        }
        let getSelector = NSSelectorFromString("hostedElements")
        let setSelector = NSSelectorFromString("setHostedElements:")
        guard visualProvider.responds(to: getSelector),
              visualProvider.responds(to: setSelector) else {
            return
        }
        typealias GetHostedIMP = @convention(c) (AnyObject, Selector) -> UInt
        typealias SetHostedIMP = @convention(c) (AnyObject, Selector, UInt) -> Void
        let getFn = unsafeBitCast(visualProvider.method(for: getSelector), to: GetHostedIMP.self)
        let current = getFn(visualProvider, getSelector)
        // bit 2 (0x4) 指示浮动视觉提供者按完整底栏宽度展开主托盘，避免空队列时主托盘缩至 336pt 靠左、与右侧搜索键之间出现巨大空隙。
        // 与队列存在时保持完全一致的宽度，增删队列时底栏无宽度跳变，且不改变任何安全区或硬编码坐标。
        let fullWidthBit: UInt = 1 << 2
        guard (current & fullWidthBit) == 0 else { return }
        let setFn = unsafeBitCast(visualProvider.method(for: setSelector), to: SetHostedIMP.self)
        setFn(visualProvider, setSelector, current | fullWidthBit)
        tabBar.setNeedsLayout()
    }

    @available(iOS 26.0, *)
    private func applyModernPadBottomBarLayoutIfNeeded() {
        guard usesModernPadBottomTabMenu, let sileoTabBar = tabBar as? TabBar else { return }
        sileoTabBar.refreshModernPadFrameIfNeeded()
        alignModernPadHostedSearchBarIfNeeded()
    }

    @objc private func handleModernPadSearchTextDidEndEditing(_ notification: Notification) {
        guard #available(iOS 26.0, *),
              usesModernPadBottomTabMenu,
              selectedTab is UISearchTab else {
            return
        }
        if let textField = notification.object as? UITextField,
           let searchField = modernSearchTabSearchController?.searchBar.searchTextField,
           textField !== searchField {
            return
        }
        scheduleModernPadHostedSearchAlignIfNeeded(afterDismiss: true)
    }

    @available(iOS 26.0, *)
    func scheduleModernPadHostedSearchAlignIfNeeded(afterDismiss: Bool = false) {
        guard usesModernPadBottomTabMenu else { return }
        if !afterDismiss {
            alignModernPadHostedSearchBarIfNeeded()
        }
        let delays: [TimeInterval] = afterDismiss ? [0.45, 0.65, 0.85] : [0.05, 0.35, 0.55]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.alignModernPadHostedSearchBarIfNeeded()
            }
        }
    }

    @available(iOS 26.0, *)
    private func alignModernPadHostedSearchBarIfNeeded() {
        guard usesModernPadBottomTabMenu,
              selectedTab is UISearchTab,
              let container = tabBar.superview,
              let hostedContainer = container.subviews.first(where: {
                  NSStringFromClass(type(of: $0)).contains("_UITabHostedSearchContainer")
              }),
              !hostedContainer.isHidden else {
            return
        }

        let tabBarFrame = tabBar.frame
        let hostedFrame = hostedContainer.frame
        guard tabBarFrame.width > 0,
              hostedFrame.width > 0,
              hostedFrame.minY >= tabBarFrame.minY - 8 else {
            return
        }

        // 等待 UIKit 进程内流体收起动画完全落位（presentationLayer 已停止纵向移动）后再写入 frame，
        // 避免在流体动画运行期间改写 model frame 导致 presentationLayer 停留在旧宽度。
        if let presentationFrame = hostedContainer.layer.presentation()?.frame,
           abs(presentationFrame.minY - hostedFrame.minY) > 0.5 {
            return
        }

        // iPadOS 26 横屏非激活态下，UIKit 会按整屏半宽（containerWidth/2 - 44）设定 _UITabHostedSearchContainer 左边界，
        // 导致与居中收窄后的左侧返回圆钮之间出现空隙；将其对齐到返回圆钮右侧 12pt 与底栏右内边距之间。
        let collapsedButtonMaxX: CGFloat
        if let returnPlatter = tabBar.subviews.first(where: { subview in
            let cls = NSStringFromClass(type(of: subview))
            return cls.contains("_UITabBarPlatterView")
                && !subview.isHidden
                && subview.bounds.width > 0
                && subview.bounds.width <= 80
        }) {
            collapsedButtonMaxX = tabBar.convert(returnPlatter.frame, to: container).maxX
        } else {
            collapsedButtonMaxX = tabBarFrame.minX + 58
        }

        let desiredMinX = collapsedButtonMaxX + 12
        let desiredMaxX = tabBarFrame.maxX - 10
        let desiredWidth = desiredMaxX - desiredMinX
        guard desiredWidth > 120,
              hostedFrame.minX > desiredMinX + 4 else {
            return
        }

        let targetFrame = CGRect(x: desiredMinX,
                                 y: hostedFrame.origin.y,
                                 width: desiredWidth,
                                 height: hostedFrame.height)
        UIView.performWithoutAnimation {
            hostedContainer.frame = targetFrame
            hostedContainer.setNeedsLayout()
            hostedContainer.layoutIfNeeded()
        }
    }

    @available(iOS 26.0, *)
    private func ensureModernPadHostedSearchOrderIfNeeded() {
        guard usesModernPadBottomTabMenu,
              let container = tabBar.superview else {
            return
        }
        // iPadOS 26/27 进入底栏搜索形变时，UIKit 会把 _UITabHostedSearchContainer 插在 Sileo.TabBar 之前（index 0）。
        // 形变期间 _UIReparentingView 的嵌套 CAPortalLayer 前向引用排在后面的 Sileo.TabBar 内部图标层与转圈角标层时，
        // CARenderServer 会跳过这些前向层，导致进入搜索左侧圆圈短暂空白、刷新角标先闪纯红点、返回菜单时首图标先消失再出现。
        // 将 _UITabHostedSearchContainer 调整到 tabBar 之上（且不影响上方可能存在的 bottomAccessory）即可在首帧彻底消除。
        guard let tabBarIndex = container.subviews.firstIndex(where: { $0 === tabBar }),
              let hostedIndex = container.subviews.firstIndex(where: {
                  NSStringFromClass(type(of: $0)).contains("_UITabHostedSearchContainer")
              }),
              hostedIndex < tabBarIndex else {
            return
        }
        container.insertSubview(container.subviews[hostedIndex], aboveSubview: tabBar)
    }

    @available(iOS 26.0, *)
    private func hasActiveModernPadMorphTransition(excluding removingSubview: UIView? = nil) -> Bool {
        let roots = [tabBar, tabBar.superview].compactMap { $0 }
        for root in roots {
            for subview in root.subviews where subview !== removingSubview {
                let cls = NSStringFromClass(type(of: subview))
                if cls.contains("Reparenting") || cls.contains("MagicMorph") || cls.contains("MorphAnimationContainer") {
                    return true
                }
                if cls.contains("_UITabHostedSearchContainer") {
                    for child in subview.subviews where child !== removingSubview {
                        let childCls = NSStringFromClass(type(of: child))
                        if childCls.contains("Reparenting") || childCls.contains("MagicMorph") || childCls.contains("MorphAnimationContainer") {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    @available(iOS 26.0, *)
    private func suspendModernPadPointerInteractionForMorphIfNeeded() {
        guard usesModernPadBottomTabMenu else { return }
        // iPadOS 触控板/鼠标指针点击搜索页左下角返回圆圈后，指针坐标仍停留在展开后“精选”标签的悬停热区内。
        // UIKit 的 UIPointerInteraction 会立刻对未选中的第一个“精选”按钮创建 UIPointerHoverEffect 镜像并隐藏其源图层，
        // 导致 MagicMorph 形变期间“精选”图标短暂脱离并被压在液态玻璃背板后面（呈现先消失再弹回的闪烁）。
        // 在形变过渡期间临时暂停 tabBar 的 UIPointerInteraction，形变结束后立即恢复原生悬停效果。
        padPointerRestoreWorkItem?.cancel()
        padPointerRestoreWorkItem = nil

        var stack: [UIView] = [tabBar]
        while let view = stack.popLast() {
            for interaction in view.interactions {
                if let pointerInteraction = interaction as? UIPointerInteraction {
                    let key = ObjectIdentifier(pointerInteraction)
                    if pointerInteraction.isEnabled {
                        suspendedPadTabBarPointerInteractions[key] = pointerInteraction
                        pointerInteraction.invalidate()
                        pointerInteraction.isEnabled = false
                    }
                }
            }
            stack.append(contentsOf: view.subviews)
        }

        guard !suspendedPadTabBarPointerInteractions.isEmpty else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreModernPadPointerInteractionIfMorphEnded(force: true)
        }
        padPointerRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: workItem)
    }

    @available(iOS 26.0, *)
    private func restoreModernPadPointerInteractionIfMorphEnded(excluding removingSubview: UIView? = nil,
                                                                force: Bool = false) {
        guard !suspendedPadTabBarPointerInteractions.isEmpty else { return }
        if !force, hasActiveModernPadMorphTransition(excluding: removingSubview) {
            return
        }
        padPointerRestoreWorkItem?.cancel()
        padPointerRestoreWorkItem = nil
        let interactions = suspendedPadTabBarPointerInteractions.values
        suspendedPadTabBarPointerInteractions.removeAll()
        for pointerInteraction in interactions {
            pointerInteraction.isEnabled = true
            pointerInteraction.invalidate()
        }
    }

    @available(iOS 26.0, *)
    private func beginTransientModernPadSelectionHighlight(for title: String?, duration: TimeInterval = 0.35) {
        guard usesModernPadBottomTabMenu else { return }
        transientPadSelectionResetWorkItem?.cancel()
        transientPadSelectionResetWorkItem = nil
        transientPadSelectedTabTitle = title
        syncModernPadSelectedTabVisualsIfNeeded()

        guard title != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishTransientModernPadSelectionHighlight(retriesRemaining: 2)
        }
        transientPadSelectionResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    @available(iOS 26.0, *)
    private func finishTransientModernPadSelectionHighlight(retriesRemaining: Int) {
        guard usesModernPadBottomTabMenu else { return }
        if retriesRemaining > 0, isModernPadLensLifted() {
            let workItem = DispatchWorkItem { [weak self] in
                self?.finishTransientModernPadSelectionHighlight(retriesRemaining: retriesRemaining - 1)
            }
            transientPadSelectionResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            return
        }
        transientPadSelectionResetWorkItem = nil
        transientPadSelectedTabTitle = nil
        syncModernPadSelectedTabVisualsIfNeeded()
    }

    @available(iOS 26.0, *)
    private func modernPadLiquidLensView() -> UIView? {
        guard let itemPlatter = tabBar.subviews.first(where: {
            NSStringFromClass(type(of: $0)).contains("_UITabBarItemPlatterView")
        }) else {
            return nil
        }
        return firstDescendant(in: itemPlatter, matching: {
            NSStringFromClass(type(of: $0)) == "_UILiquidLensView"
        })
    }

    @available(iOS 26.0, *)
    private func isModernPadLensLifted() -> Bool {
        guard let lensView = modernPadLiquidLensView() else { return false }
        let liftedSelector = NSSelectorFromString("lifted")
        guard lensView.responds(to: liftedSelector) else { return false }
        typealias GetBoolIMP = @convention(c) (AnyObject, Selector) -> ObjCBool
        let getLifted = unsafeBitCast(lensView.method(for: liftedSelector), to: GetBoolIMP.self)
        return getLifted(lensView, liftedSelector).boolValue
    }

    @available(iOS 26.0, *)
    private func syncModernPadSelectedTabVisualsIfNeeded(force: Bool = false) {
        guard usesModernPadBottomTabMenu, !tabs.isEmpty else { return }
        // iPadOS 宽底栏（>1000pt）切换远端标签时，液态玻璃透镜飞行到位前新标签在 ContentView 中仍为黑色。
        // 仅在切换过渡期短暂为目标标签同步主题色，透镜落位（DestOutView 已完全遮罩 ContentView）后自动恢复原生模板态，
        // 从而同时保证点击切换 0ms 变色与长按拖动透镜时绝不出现双标签同时高亮。
        let resolvedTitle = transientPadSelectedTabTitle

        guard let itemPlatter = tabBar.subviews.first(where: {
            NSStringFromClass(type(of: $0)).contains("_UITabBarItemPlatterView")
        }) else {
            return
        }
        guard let contentView = itemPlatter.subviews.first(where: { subview in
            let cls = NSStringFromClass(type(of: subview))
            return cls.contains("ContentView") && !cls.contains("Selected")
        }) else {
            return
        }

        let traits = tabBar.traitCollection
        let selectedColor = tabBar.tintColor ?? UIColor.tintColor
        let resolvedSelectedColor = selectedColor.resolvedColor(with: traits)
        let unselectedColor = tabBar.unselectedItemTintColor ?? .label

        let buttons = allDescendants(in: contentView, matching: {
            NSStringFromClass(type(of: $0)) == "_UITabButton"
        })
        for button in buttons {
            guard let title = tabButtonTitle(in: button), !title.isEmpty else { continue }
            let isSelected = (resolvedTitle != nil && title == resolvedTitle)
            applyModernPadTabButtonStyle(button,
                                         isSelected: isSelected,
                                         selectedColor: selectedColor,
                                         resolvedSelectedColor: resolvedSelectedColor,
                                         unselectedColor: unselectedColor,
                                         traits: traits,
                                         force: force)
        }
    }

    private func applyModernPadTabButtonStyle(_ button: UIView,
                                              isSelected: Bool,
                                              selectedColor: UIColor,
                                              resolvedSelectedColor: UIColor,
                                              unselectedColor: UIColor,
                                              traits: UITraitCollection,
                                              force: Bool) {
        let targetTextColor = isSelected ? selectedColor : unselectedColor
        var stack = button.subviews
        while let view = stack.popLast() {
            if NSStringFromClass(type(of: view)) == "_UIBarBadgeView" {
                continue
            }
            if let imageView = view as? UIImageView, let image = imageView.image {
                if isSelected {
                    if force || image.renderingMode != .alwaysOriginal {
                        imageView.image = image
                            .withRenderingMode(.alwaysTemplate)
                            .withTintColor(resolvedSelectedColor, renderingMode: .alwaysOriginal)
                    }
                } else if image.renderingMode != .alwaysTemplate {
                    imageView.image = image.withRenderingMode(.alwaysTemplate)
                }
            } else if let label = view as? UILabel {
                if let attributed = label.attributedText, attributed.length > 0 {
                    let existingColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
                    if force || !colorsMatch(existingColor, targetTextColor, traits: traits) {
                        let mutable = NSMutableAttributedString(attributedString: attributed)
                        mutable.addAttribute(.foregroundColor,
                                             value: targetTextColor,
                                             range: NSRange(location: 0, length: mutable.length))
                        label.attributedText = mutable
                    }
                }
                if force || !colorsMatch(label.textColor, targetTextColor, traits: traits) {
                    label.textColor = targetTextColor
                }
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    private func colorsMatch(_ lhs: UIColor?, _ rhs: UIColor, traits: UITraitCollection) -> Bool {
        guard let lhs else { return false }
        return lhs.resolvedColor(with: traits).isEqual(rhs.resolvedColor(with: traits))
    }

    @available(iOS 26.0, *)
    private func accelerateModernPadLensUnliftIfNeeded() {
        guard usesModernPadBottomTabMenu,
              !(selectedTab is UISearchTab) else {
            return
        }
        let isMorphing = tabBar.subviews.contains { subview in
            let cls = NSStringFromClass(type(of: subview))
            return cls.contains("Reparenting") || cls.contains("MagicMorph")
        }
        guard !isMorphing,
              let lensView = modernPadLiquidLensView() else {
            return
        }

        let timerSelector = NSSelectorFromString("unliftDelayTimer")
        if lensView.responds(to: timerSelector),
           let timer = lensView.perform(timerSelector)?.takeUnretainedValue() as? Timer,
           timer.isValid {
            timer.fire()
            return
        }

        let liftedSelector = NSSelectorFromString("lifted")
        let actuallySetLiftedSelector = NSSelectorFromString("actuallySetLifted:animated:alongsideAnimations:completion:")
        guard lensView.responds(to: liftedSelector),
              lensView.responds(to: actuallySetLiftedSelector) else {
            return
        }
        typealias GetBoolIMP = @convention(c) (AnyObject, Selector) -> ObjCBool
        typealias ActuallySetLiftedIMP = @convention(c) (AnyObject, Selector, ObjCBool, ObjCBool, AnyObject?, AnyObject?) -> Void
        let getLifted = unsafeBitCast(lensView.method(for: liftedSelector), to: GetBoolIMP.self)
        guard getLifted(lensView, liftedSelector).boolValue else {
            return
        }
        let actuallySetLifted = unsafeBitCast(lensView.method(for: actuallySetLiftedSelector), to: ActuallySetLiftedIMP.self)
        actuallySetLifted(lensView, actuallySetLiftedSelector, ObjCBool(false), ObjCBool(true), nil, nil)
    }

    @available(iOS 26.0, *)
    func setModernPadSearchActive(_ isActive: Bool) {
        guard usesModernPadBottomTabMenu else { return }
        if !isActive {
            scheduleModernPadHostedSearchAlignIfNeeded(afterDismiss: true)
        }
        guard isModernPadSearchActive != isActive else { return }
        isModernPadSearchActive = isActive
        guard popupIsPresented, !isQueueSheetEffectivelyVisible, !isPresentingQueueSheet else {
            return
        }
        if isActive {
            setBottomAccessory(nil, animated: true)
            ensureModernPadFullWidthTabPlatterIfNeeded()
        } else {
            restoreLiquidGlassQueueBarIfNeeded(animated: true)
        }
    }

    @available(iOS 26.0, *)
    private func deactivateModernPadSearchForTabSwitchIfNeeded() {
        guard usesModernPadBottomTabMenu else { return }
        if let searchController = modernSearchTabSearchController, searchController.isActive {
            UIView.performWithoutAnimation {
                searchController.isActive = false
            }
        }
        isModernPadSearchActive = false
        if popupIsPresented, !isQueueSheetEffectivelyVisible, !isPresentingQueueSheet, bottomAccessory == nil {
            restoreLiquidGlassQueueBarIfNeeded(animated: true)
        } else {
            ensureModernPadFullWidthTabPlatterIfNeeded()
        }
    }

    func configureSearchTabIfNeeded() {
        guard #available(iOS 26.0, *),
              usesModernTabMenu,
              tabs.isEmpty,
              let controllers = super.viewControllers else {
            return
        }

        if usesModernPadBottomTabMenu {
            prepareModernPadBottomTabTraitsIfNeeded(in: viewIfLoaded?.window
                ?? (UIApplication.shared.delegate as? SileoAppDelegate)?.window)
        }

        let previousController = super.selectedViewController
        let configuredTabs = makeTabs(from: controllers)
        if #available(iOS 27.0, *),
           let searchTab = configuredTabs.first(where: { $0 is UISearchTab }) {
            // iOS 27 需要通过 prominentTabIdentifier 指定独立的底部搜索入口。
            prominentTabIdentifier = searchTab.identifier
        }
        if usesModernPadBottomTabMenu {
            mode = .tabBar
        }
        setTabs(configuredTabs, animated: false)
        // 按 Demo v34 顺序：iOS 26 在 setTabs 后、selectedTab 前初始化 AnchoredBadgeRenderer。
        if #unavailable(iOS 27.0) {
            if anchoredBadges == nil {
                anchoredBadges = AnchoredBadgeRenderer(
                    tabBar: tabBar,
                    hostView: view,
                    isRefreshing: isSourcesRefreshing,
                    countValue: packageBadgeValue,
                    countBadgeColor: packageBadgeColor
                )
            } else {
                anchoredBadges?.setRefreshing(isSourcesRefreshing, in: tabBar)
                anchoredBadges?.setCount(packageBadgeValue, badgeColor: packageBadgeColor, in: tabBar)
            }
        }
        // 预先触发视图控制器提供闭包，确保各子控制器在首次切换前也能关联到对应 UITab。
        _ = tabs.map(\.viewController)
        if usesModernPadBottomTabMenu {
            syncModernPadContentTabTraits()
        }
        let initialTab = tabs.first { $0.viewController === previousController } ?? tabs.first
        if #available(iOS 27.0, *) {
            // iOS 27 首次选中后才重新计算中文标签高度，在首帧提交前完成各标签的布局。
            UIView.performWithoutAnimation {
                for tab in tabs where !(tab is UISearchTab) {
                    selectedTab = tab
                    view.layoutIfNeeded()
                }
                selectedTab = initialTab
                view.layoutIfNeeded()
            }
        } else {
            selectedTab = initialTab
        }
        if let initialTab, !(initialTab is UISearchTab) {
            lastNonSearchTabIdentifier = initialTab.identifier
        }
        if isSourcesRefreshing {
            syncVisualProviderItem(tabBar.items?[safe: 2] ?? sileoViewControllers?[safe: 2]?.tabBarItem)
        }
        if packageBadgeValue != nil {
            syncVisualProviderItem(tabBar.items?[safe: 3] ?? sileoViewControllers?[safe: 3]?.tabBarItem)
        }
        updateModernTabBadges()
        updateModernTabBadgeDisplayLink()
        if usesModernPadBottomTabMenu {
            ensureModernPadFullWidthTabPlatterIfNeeded()
            applyModernPadBottomBarLayoutIfNeeded()
            ensureModernPadHostedSearchOrderIfNeeded()
        }
        if usesFloatingQueueCardOnPhone {
            registerLiquidGlassContentScrollView()
        }
    }

    @available(iOS 26.0, *)
    private func makeTabs(from controllers: [UIViewController]) -> [UITab] {
        let titleKeys = ["Featured_Page", "News_Page", "Sources_Page", "Packages_Page", "Search_Page"]
        return controllers.enumerated().map { index, controller in
            if let existingTab = controller.tab {
                return existingTab
            }
            let previousItem = controller.tabBarItem!
            let title = titleKeys.indices.contains(index) ? String(localizationKey: titleKeys[index]) : (previousItem.title ?? "")

            let isSearchController = (controller as? UINavigationController)
                .flatMap { $0.viewControllers.first as? PackageListViewController }?
                .showSearchField == true

            if isSearchController {
                let searchTab = UISearchTab { _ in controller }
                searchTab.title = title
                // 首次进入先展示最近搜索，点搜索框或再次点搜索标签时才弹出键盘。
                searchTab.automaticallyActivatesSearch = false
                return searchTab
            }

            let rawImage = previousItem.image ?? (index == 0 ? UIImage(systemName: "star.fill") : nil)
            let image = normalizedTabImage(rawImage)

            let badgeValue: String?
            switch index {
            case 2:
                badgeValue = isSourcesRefreshing ? NativeRefreshBadge.value : nil
            case 3:
                let resolved = packageBadgeValue ?? Self.normalizedBadgeValue(previousItem.badgeValue)
                packageBadgeValue = resolved
                if packageBadgeColor == nil {
                    packageBadgeColor = previousItem.badgeColor
                }
                badgeValue = resolved
            default:
                badgeValue = Self.normalizedBadgeValue(previousItem.badgeValue)
            }

            // 按 Demo v34 方式只配置 title / image / badgeValue，不设置 UITab.selectedImage；
            // 不单独写入 badgeColor，以免覆盖 iOS 26 透明外观设置。
            let item = UITabBarItem(title: title, image: image, tag: previousItem.tag)
            item.badgeValue = badgeValue
            item.badgeColor = nil
            controller.tabBarItem = item

            let identifier = SileoTabIdentifier.identifier(for: index)
            let tab = UITab(title: title, image: image, identifier: identifier) { _ in controller }
            tab.badgeValue = badgeValue
            return tab
        }
    }

    @available(iOS 26.0, *)
    private func normalizedTabImage(_ image: UIImage?) -> UIImage? {
        guard var image else { return nil }
        if !image.isSymbolImage {
            let tinted = image.withTintColor(.black, renderingMode: .alwaysOriginal)
            // 自定义图标使用相同画布，避免 UIKit 按不同图片高度挤压菜单标题。
            let size = CGSize(width: 26, height: 26)
            let bounds = CGRect(origin: CGPoint(x: (size.width - tinted.size.width) / 2,
                                                y: (size.height - tinted.size.height) / 2),
                                size: tinted.size)
            image = UIGraphicsImageRenderer(size: size).image { _ in
                tinted.draw(in: bounds)
            }.withBaselineOffset(fromBottom: 0)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private static func normalizedBadgeValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    @available(iOS 26.0, *)
    private func tab(withIdentifier identifier: String) -> UITab? {
        tabs.first { $0.identifier == identifier }
    }

    @available(iOS 26.0, *)
    private func syncVisualProviderItem(_ item: UITabBarItem?) {
        guard let item,
              let visualProviderIvar = class_getInstanceVariable(UITabBar.self, "_visualProvider"),
              let visualProvider = object_getIvar(tabBar, visualProviderIvar) as? NSObject,
              NSStringFromClass(type(of: visualProvider)).contains("_UITabBarVisualProvider_Floating") else {
            return
        }
        // iOS 26 在 setTabs 之后动态更新 UITab.badgeValue 不会自动通知浮动视觉提供者刷新按钮角标，
        // 显式触发 updateItem: 才能在不重建整条标签栏的前提下立即生成或移除 _UIBarBadgeView。
        let selector = NSSelectorFromString("updateItem:")
        guard visualProvider.responds(to: selector) else {
            return
        }
        typealias UpdateItemImplementation = @convention(c) (AnyObject, Selector, UITabBarItem) -> Void
        let implementation = visualProvider.method(for: selector)
        let updateItem = unsafeBitCast(implementation, to: UpdateItemImplementation.self)
        updateItem(visualProvider, selector, item)
        syncCompactPlatterBadgesIfNeeded(allowDuringMorph: true)
        tabBar.setNeedsLayout()
    }

    @available(iOS 26.0, *)
    private func syncCompactPlatterBadgesIfNeeded(allowDuringMorph: Bool = false) {
        guard usesModernTabMenu, !tabs.isEmpty else { return }
        if !allowDuringMorph {
            let isMorphing = tabBar.subviews.contains { subview in
                let cls = NSStringFromClass(type(of: subview))
                return cls.contains("Reparenting") || cls.contains("MagicMorph")
            }
            if isMorphing { return }
        }

        let setBadgeSelector = NSSelectorFromString("_setBadgeValue:")
        typealias SetBadgeValueIMP = @convention(c) (AnyObject, Selector, NSString?) -> Void

        var didUpdateCompactBadge = false
        for subview in tabBar.subviews {
            let className = NSStringFromClass(type(of: subview))
            // UIKit 的 _UITabBarVisualProvider_Floating.updateItem: 不会同步紧凑托盘内的复用按钮
            // （collapseButton）。注意 iOS 26 上展开托盘与紧凑托盘同名（均为 _UITabBarPlatterView），
            // 因此必须按内部 `_UITabButton` 数量严格等于 1 来识别紧凑托盘，避免误判展开托盘导致布局循环。
            guard className.contains("PlatterView"),
                  !className.contains("ItemPlatterView") else {
                continue
            }
            let buttons = allDescendants(in: subview, matching: { NSStringFromClass(type(of: $0)) == "_UITabButton" })
            guard buttons.count == 1,
                  let button = buttons.first,
                  button.responds(to: setBadgeSelector),
                  let title = tabButtonTitle(in: button),
                  !title.isEmpty else {
                continue
            }

            let matchedTab = tabs.first { !($0 is UISearchTab) && $0.title == title }
            let matchedItem = tabBar.items?.first { $0.title == title }
            guard matchedTab != nil || matchedItem != nil else { continue }

            let expectedBadge = Self.normalizedBadgeValue(matchedTab?.badgeValue ?? matchedItem?.badgeValue)
            let currentBadge = currentCompactBadgeValue(in: subview)
            let buttonID = ObjectIdentifier(button)
            guard currentBadge != expectedBadge else {
                if lastCompactBadgeSyncAttempt?.buttonID == buttonID {
                    lastCompactBadgeSyncAttempt = nil
                }
                continue
            }

            let attempt = CompactBadgeSyncAttempt(
                buttonID: buttonID,
                title: title,
                expected: expectedBadge,
                observed: currentBadge
            )
            if !allowDuringMorph, lastCompactBadgeSyncAttempt == attempt {
                continue
            }
            lastCompactBadgeSyncAttempt = attempt

            let imp = button.method(for: setBadgeSelector)
            let setBadgeValue = unsafeBitCast(imp, to: SetBadgeValueIMP.self)
            setBadgeValue(button, setBadgeSelector, expectedBadge as NSString?)
            didUpdateCompactBadge = true
        }

        if didUpdateCompactBadge {
            tabBar.setNeedsLayout()
        }
    }

    private func allDescendants(in root: UIView, matching predicate: (UIView) -> Bool) -> [UIView] {
        var matches: [UIView] = []
        var stack = root.subviews
        while let view = stack.popLast() {
            if predicate(view) {
                matches.append(view)
            }
            stack.append(contentsOf: view.subviews)
        }
        return matches
    }

    private func firstDescendant(in root: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
        for subview in root.subviews {
            if predicate(subview) {
                return subview
            }
            if let match = firstDescendant(in: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func tabButtonTitle(in button: UIView) -> String? {
        var stack = button.subviews
        while let view = stack.popLast() {
            if NSStringFromClass(type(of: view)) == "_UIBarBadgeView" {
                continue
            }
            if let label = view as? UILabel, let text = label.text, !text.isEmpty {
                return text
            }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func currentCompactBadgeValue(in platter: UIView) -> String? {
        guard let badgeView = firstDescendant(in: platter, matching: {
            NSStringFromClass(type(of: $0)) == "_UIBarBadgeView" && !$0.isHidden
        }) else {
            return nil
        }
        if let label = firstDescendant(in: badgeView, matching: { $0 is UILabel }) as? UILabel {
            return label.text ?? ""
        }
        return ""
    }

    private var modernTabBadgeSearchRoot: UIView {
        guard isViewLoaded, tabBar.isDescendant(of: view) else {
            return tabBar
        }
        // iOS 27 竖排浮动标签栏（如 iPhone Duo 的 _UITabBarVisualProvider_FloatingLandscape）
        // 会把 _UITabBarItemPlatterView 与 _UIBarBadgeView 托管在 _UITabContainerView 下的
        // _UIFloatingBarContainerView，而不是 tabBar 子树内部。
        // 沿 tabBar 向上取 TabBarController.view 的直接容器子视图，即可覆盖底栏与侧边浮动栏，
        // 同时不进入兄弟分支 UITransitionView 里的业务页面。
        var container: UIView = tabBar
        while let superview = container.superview, superview !== view {
            container = superview
        }
        return container
    }

    func setSourcesRefreshing(_ refreshing: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.setSourcesRefreshing(refreshing)
            }
            return
        }
        guard usesModernTabMenu else { return }
        let badgeValue = refreshing ? NativeRefreshBadge.value : nil
        let stateChanged = isSourcesRefreshing != refreshing
        isSourcesRefreshing = refreshing

        if #available(iOS 26.0, *) {
            let sourcesTab = tab(withIdentifier: SileoTabIdentifier.sources)
            var didMutateBadge = stateChanged
            if sourcesTab?.badgeValue != badgeValue {
                sourcesTab?.badgeValue = badgeValue
                didMutateBadge = true
            }
            let sourcesController = sourcesTab?.viewController ?? sileoViewControllers?[safe: 2]
            if sourcesController?.tabBarItem.badgeColor != nil {
                sourcesController?.tabBarItem.badgeColor = nil
                didMutateBadge = true
            }
            if sourcesController?.tabBarItem.badgeValue != badgeValue {
                sourcesController?.tabBarItem.badgeValue = badgeValue
                didMutateBadge = true
            }
            if didMutateBadge {
                lastCompactBadgeSyncAttempt = nil
                syncVisualProviderItem(tabBar.items?[safe: 2] ?? sourcesController?.tabBarItem)
            }
            if let anchoredBadges {
                anchoredBadges.setRefreshing(refreshing, in: tabBar)
            } else if !refreshing {
                nativeRefreshBadge.update(in: modernTabBadgeSearchRoot, isRefreshing: false)
            }
            if didMutateBadge {
                updateModernTabBadges()
                updateModernTabBadgeDisplayLink()
            } else if refreshing && badgeDisplayLink == nil {
                updateModernTabBadgeDisplayLink()
            }
        }
    }

    func setTabBadgeValue(_ value: String?, for controller: UIViewController) -> Bool {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                _ = self.setTabBadgeValue(value, for: controller)
            }
            return true
        }
        guard usesModernTabMenu else { return false }
        guard #available(iOS 26.0, *) else { return false }

        let sourcesTab = tab(withIdentifier: SileoTabIdentifier.sources)
        let packagesTab = tab(withIdentifier: SileoTabIdentifier.packages)
        let isSources = controller.tab?.identifier == SileoTabIdentifier.sources
            || sourcesTab?.viewController === controller
            || sileoViewControllers?[safe: 2] === controller
        let isPackages = controller.tab?.identifier == SileoTabIdentifier.packages
            || packagesTab?.viewController === controller
            || sileoViewControllers?[safe: 3] === controller

        if isSources {
            let refreshing = (value != nil && !value!.isEmpty)
            setSourcesRefreshing(refreshing)
            return true
        }

        if isPackages {
            let normalized = Self.normalizedBadgeValue(value)
            let customColor = controller.tabBarItem.badgeColor
            let stateChanged = packageBadgeValue != normalized
            packageBadgeValue = normalized
            if customColor != nil {
                packageBadgeColor = customColor
            }
            var didMutateBadge = stateChanged
            let targetTab = controller.tab ?? packagesTab
            if targetTab?.badgeValue != normalized {
                targetTab?.badgeValue = normalized
                didMutateBadge = true
            }
            if controller.tabBarItem.badgeColor != nil {
                controller.tabBarItem.badgeColor = nil
                didMutateBadge = true
            }
            if controller.tabBarItem.badgeValue != normalized {
                controller.tabBarItem.badgeValue = normalized
                didMutateBadge = true
            }
            if didMutateBadge {
                lastCompactBadgeSyncAttempt = nil
                syncVisualProviderItem(tabBar.items?[safe: 3] ?? controller.tabBarItem)
            }
            anchoredBadges?.setCount(normalized, badgeColor: packageBadgeColor, in: tabBar)
            updateModernTabBadges()
            updateModernTabBadgeDisplayLink()
            return true
        }

        return false
    }

    @available(iOS 26.0, *)
    private var needsModernTabBadgeDisplayLink: Bool {
        guard usesModernTabMenu,
              isViewLoaded,
              isModernTabBarVisible,
              view.window != nil,
              UIApplication.shared.applicationState != .background else {
            return false
        }
        if let anchoredBadges {
            return anchoredBadges.needsDisplayUpdates
        }
        return isSourcesRefreshing
    }

    private func updateModernTabBadgeDisplayLink() {
        guard #available(iOS 26.0, *), usesModernTabMenu else { return }
        guard needsModernTabBadgeDisplayLink else {
            stopModernTabBadgeDisplayLink()
            return
        }
        let wantsHighRate = anchoredBadges?.needsHighFrameRate ?? false
        let range = wantsHighRate
            ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
        if let link = badgeDisplayLink {
            if badgeDisplayLinkUsesHighRate != wantsHighRate {
                link.preferredFrameRateRange = range
                badgeDisplayLinkUsesHighRate = wantsHighRate
            }
            return
        }
        let target = ModernBadgeDisplayTick(owner: self)
        badgeTickTarget = target
        let link = CADisplayLink(target: target, selector: #selector(ModernBadgeDisplayTick.tick(_:)))
        link.preferredFrameRateRange = range
        link.add(to: .main, forMode: .common)
        badgeDisplayLink = link
        badgeDisplayLinkUsesHighRate = wantsHighRate
    }

    private func stopModernTabBadgeDisplayLink() {
        badgeDisplayLink?.invalidate()
        badgeDisplayLink = nil
        badgeTickTarget = nil
        badgeDisplayLinkUsesHighRate = false
    }

    fileprivate func updateModernTabBadges() {
        guard #available(iOS 26.0, *), usesModernTabMenu, isViewLoaded else { return }
        guard view.window != nil else {
            anchoredBadges?.detach()
            nativeBadgePortalLift?.deactivate()
            return
        }
        syncCompactPlatterBadgesIfNeeded()
        if let anchoredBadges {
            let wasFallback = anchoredBadges.isUsingNativeFallback
            let isSearchSelected = selectedTab is UISearchTab
            let primaryID: String?
            if let current = selectedTab, !(current is UISearchTab) {
                primaryID = current.identifier
            } else {
                primaryID = lastNonSearchTabIdentifier
            }
            anchoredBadges.update(
                in: tabBar,
                isSearchTabSelected: isSearchSelected,
                selectedPrimaryIsSources: primaryID == SileoTabIdentifier.sources,
                selectedPrimaryIsPackages: primaryID == SileoTabIdentifier.packages
            )
            if wasFallback != anchoredBadges.isUsingNativeFallback {
                updateModernTabBadgeDisplayLink()
            }
        } else {
            nativeRefreshBadge.update(in: modernTabBadgeSearchRoot, isRefreshing: isSourcesRefreshing)
            nativeBadgePortalLift?.update(in: tabBar)
        }
    }

    @objc private func handleModernBadgeDidEnterBackground() {
        stopModernTabBadgeDisplayLink()
        nativeBadgePortalLift?.deactivate()
    }

    @objc private func handleModernBadgeWillEnterForeground() {
        guard usesModernTabMenu else { return }
        anchoredBadges?.invalidateLayout()
        updateModernTabBadges()
        updateModernTabBadgeDisplayLink()
    }

    fileprivate func handleProgrammaticTabSelection() {
        guard #available(iOS 26.0, *), usesModernTabMenu else { return }
        if let current = selectedTab, !(current is UISearchTab) {
            lastNonSearchTabIdentifier = current.identifier
            deactivateModernPadSearchForTabSwitchIfNeeded()
        }
        if usesModernPadBottomTabMenu {
            ensureModernPadHostedSearchOrderIfNeeded()
            if let current = selectedTab, !(current is UISearchTab) {
                beginTransientModernPadSelectionHighlight(for: current.title)
            } else {
                beginTransientModernPadSelectionHighlight(for: nil)
            }
        }
        anchoredBadges?.invalidateLayout()
        updateModernTabBadges()
        if usesFloatingQueueCardOnPhone {
            registerLiquidGlassContentScrollView()
        } else if usesModernPadBottomTabMenu {
            (sileoSelectedViewController as? SourcesSplitViewController)?.padScrollCoordinator?.markNeedsRebind()
        }
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab is UISearchTab {
            nativeBadgePortalLift?.deactivate()
        } else if #available(iOS 26.0, *) {
            deactivateModernPadSearchForTabSwitchIfNeeded()
        }
        if #available(iOS 26.0, *) {
            if usesModernPadBottomTabMenu {
                ensureModernPadHostedSearchOrderIfNeeded()
                if tab is UISearchTab || selectedTab is UISearchTab {
                    suspendModernPadPointerInteractionForMorphIfNeeded()
                }
                if !(tab is UISearchTab) {
                    let duration: TimeInterval = (selectedTab is UISearchTab) ? 0.45 : 0.35
                    beginTransientModernPadSelectionHighlight(for: tab.title, duration: duration)
                } else {
                    beginTransientModernPadSelectionHighlight(for: nil)
                }
            }
            syncCompactPlatterBadgesIfNeeded(allowDuringMorph: true)
        }
        guard let controller = tab.viewController else { return false }
        // 由 UIKit 完成标签与搜索栏的同一次过渡，避免手动切换后再取消选择导致旧菜单残留。
        return self.tabBarController(tabBarController, shouldSelect: controller)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        if !(selectedTab is UISearchTab) {
            lastNonSearchTabIdentifier = selectedTab.identifier
            if #available(iOS 26.0, *) {
                deactivateModernPadSearchForTabSwitchIfNeeded()
            }
        } else if let previousTab, !(previousTab is UISearchTab) {
            lastNonSearchTabIdentifier = previousTab.identifier
        }
        if #available(iOS 26.0, *) {
            if anchoredBadges == nil {
                syncCompactPlatterBadgesIfNeeded(allowDuringMorph: true)
                if isSourcesRefreshing {
                    nativeRefreshBadge.update(in: modernTabBadgeSearchRoot, isRefreshing: true)
                }
            }
            if usesModernPadBottomTabMenu {
                ensureModernPadHostedSearchOrderIfNeeded()
                if selectedTab is UISearchTab || previousTab is UISearchTab {
                    suspendModernPadPointerInteractionForMorphIfNeeded()
                }
                if !(selectedTab is UISearchTab) {
                    let duration: TimeInterval = (previousTab is UISearchTab) ? 0.45 : 0.35
                    beginTransientModernPadSelectionHighlight(for: selectedTab.title, duration: duration)
                    if let previousTab, !(previousTab is UISearchTab), selectedTab !== previousTab {
                        DispatchQueue.main.async { [weak self] in
                            self?.accelerateModernPadLensUnliftIfNeeded()
                        }
                    }
                } else {
                    beginTransientModernPadSelectionHighlight(for: nil)
                    scheduleModernPadHostedSearchAlignIfNeeded()
                }
            }
        }
        guard let controller = selectedTab.viewController else { return }
        self.tabBarController(tabBarController, didSelect: controller)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if usesModernTabMenu {
            anchoredBadges?.invalidateLayout()
            updateModernTabBadges()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if #available(iOS 26.0, *), usesModernTabMenu {
            isModernTabBarVisible = true
            if usesModernPadBottomTabMenu {
                prepareModernPadBottomTabTraitsIfNeeded(in: view.window)
            }
            if usesFloatingQueueCardOnPhone {
                registerLiquidGlassContentScrollView()
            }
            updateModernTabBadges()
            updateModernTabBadgeDisplayLink()
        }
        
        self.updatePopup()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if usesModernTabMenu {
            isModernTabBarVisible = false
            stopModernTabBadgeDisplayLink()
            if view.window == nil {
                anchoredBadges?.detach()
                nativeBadgePortalLift?.deactivate()
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard usesModernTabMenu else { return }
        anchoredBadges?.invalidateLayout()
        nativeBadgePortalLift?.deactivate()
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            if #available(iOS 26.0, *), self.usesModernPadBottomTabMenu {
                self.syncModernPadContentTabTraits()
                self.applyModernPadBottomBarLayoutIfNeeded()
            }
            self.anchoredBadges?.invalidateLayout()
            self.updateModernTabBadges()
        }, completion: { [weak self] _ in
            guard let self else { return }
            if #available(iOS 26.0, *), self.usesModernPadBottomTabMenu {
                self.syncModernPadContentTabTraits()
                self.applyModernPadBottomBarLayoutIfNeeded()
            }
            self.anchoredBadges?.invalidateLayout()
            self.updateModernTabBadges()
            self.updateModernTabBadgeDisplayLink()
        })
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        shouldSelectIndex = tabBarController.sileoSelectedIndex
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #available(iOS 26.0, *), usesModernTabMenu {
            anchoredBadges?.invalidateLayout()
            updateModernTabBadges()
            if usesFloatingQueueCardOnPhone {
                registerLiquidGlassContentScrollView()
            } else if usesModernPadBottomTabMenu {
                (viewController as? SourcesSplitViewController)?.padScrollCoordinator?.markNeedsRebind()
            }
            // iOS 26 在切换顶层标签时会重建滚动观察关系，并可能把收缩策略临时重置为 .never。
            // 等本轮容器布局结束后重新注册当前列表并恢复策略，避免“软件源”页丢失队列收缩能力。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.usesFloatingQueueCardOnPhone {
                    self.registerLiquidGlassContentScrollView()
                }
                self.restoreLiquidGlassMinimizeBehaviorIfNeeded()
                self.anchoredBadges?.invalidateLayout()
                self.updateModernTabBadges()
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
            if usesModernTabMenu {
                anchoredBadges?.invalidateLayout()
                updateModernTabBadges()
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

        restoreLiquidGlassMinimizeBehaviorIfNeeded()

        // 当前页面可能是导航栈里的详情页，把实际滚动视图直接交给顶部导航容器。
        if !isPackagesTabScrollView(scrollView) {
            registerLiquidGlassScrollView(scrollView, for: .top, force: false)
        }
        if isSourcesScrollView(scrollView) {
            driveSourcesQueueMinimizeIfNeeded(from: scrollView)
        } else {
            registerLiquidGlassScrollView(scrollView, for: .bottom, force: false)
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
            let wasMinimized = currentLiquidGlassMorphTarget() == 2
            let needsRegistration = wasMinimized || sourcesQueueIsMinimized
            if wasMinimized {
                sourcesQueueIsMinimized = true
                setLiquidGlassQueueMinimized(false)
            } else {
                sourcesQueueIsMinimized = false
            }
            registerSourcesScrollView(scrollView, force: needsRegistration)
            return
        }

        if currentLiquidGlassMorphTarget() == 2 {
            let didMinimize = !sourcesQueueIsMinimized
            sourcesQueueIsMinimized = true
            registerSourcesQueueTrackingScrollView(force: didMinimize)
            return
        }

        // 第一次向内容下方滚动时让 UIKit 自己完成完整的 accessory/tab morph；
        // 这样系统会正确生成“当前标签 + 队列 + 搜索”的三段紧凑布局。
        let wasMinimized = sourcesQueueIsMinimized
        sourcesQueueIsMinimized = false
        registerSourcesScrollView(scrollView, force: wasMinimized)
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
    private func registerLiquidGlassScrollView(_ scrollView: UIScrollView,
                                              for edge: NSDirectionalRectEdge,
                                              force: Bool) {
        let selectedController = sileoSelectedViewController
        // 读取当前实际绑定，避免本地缓存遗漏 UIKit 重建后的观察关系。
        // 先判断两个容器，再执行设置，防止父容器的设置影响子容器的判断。
        let needsContainerRegistration = force || contentScrollView(for: edge) !== scrollView
        let needsSelectedRegistration = force || selectedController?.contentScrollView(for: edge) !== scrollView
        if needsContainerRegistration {
            setContentScrollView(scrollView, for: edge)
        }
        if needsSelectedRegistration {
            selectedController?.setContentScrollView(scrollView, for: edge)
        }
    }

    @available(iOS 26.0, *)
    private func registerSourcesScrollView(_ scrollView: UIScrollView, force: Bool = true) {
        // 生命周期和拖动起点保留强制注册，仅连续滚动时按当前绑定去重。
        registerLiquidGlassScrollView(scrollView, for: .bottom, force: force)
    }

    @available(iOS 26.0, *)
    private func registerSourcesQueueTrackingScrollView(force: Bool = true) {
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

        let needsReparenting = trackingScrollView.superview !== sileoSelectedViewController.view
        if needsReparenting {
            trackingScrollView.removeFromSuperview()
            sileoSelectedViewController.view.insertSubview(trackingScrollView, at: 0)
        }
        registerLiquidGlassScrollView(trackingScrollView, for: .bottom, force: force || needsReparenting)
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
        guard usesModernTabMenu,
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
        guard usesFloatingQueueCardOnPhone,
              let sileoSelectedViewController,
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
              !isQueueSheetEffectivelyVisible,
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
              !isQueueSheetEffectivelyVisible,
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
        if #available(iOS 26.0, *) {
            restoreModernPadTraitsIfNeeded(for: downloadsController)
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
        if #available(iOS 26.0, *), usesModernPadBottomTabMenu, transientPadSelectedTabTitle != nil {
            syncModernPadSelectedTabVisualsIfNeeded(force: true)
        }

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
            let appearance = source.copy()
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

        if let anchoredBadges {
            // 分别维护 standardAppearance 与 scrollEdgeAppearance 原样式，主题变化后继续保持 iOS 26 透明角标外观。
            anchoredBadges.updateBaseAppearances(in: tabBar, transform: appearanceByUpdatingSelectedColor)
        } else {
            let standardAppearance = appearanceByUpdatingSelectedColor(tabBar.standardAppearance)
            tabBar.standardAppearance = standardAppearance
            if #available(iOS 15.0, *) {
                let source = tabBar.scrollEdgeAppearance ?? standardAppearance
                tabBar.scrollEdgeAppearance = appearanceByUpdatingSelectedColor(source)
            }
        }

        for item in tabBar.items ?? [] {
            var titleAttributes = item.titleTextAttributes(for: .selected) ?? [:]
            titleAttributes[.foregroundColor] = tintColor
            item.setTitleTextAttributes(titleAttributes, for: .selected)
        }

        tabBar.setNeedsLayout()
    }

    private func updateLiquidGlassTabBarMinimizeBehavior() {
        guard #available(iOS 26.0, *), usesModernTabMenu else {
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
        if #available(iOS 26.0, *), usesModernPadBottomTabMenu {
            applyModernPadBottomBarLayoutIfNeeded()
        }
        if usesModernTabMenu {
            anchoredBadges?.invalidateLayout()
            updateModernTabBadges()
        }
        
        if self.tabBar.itemPositioning != .centered {
            self.tabBar.itemPositioning = .centered
        }
        if #available(iOS 26.0, *), usesModernTabMenu {
            // accessory 的首次布局可能会重建标签栏，布局完成后再次保持当前策略。
            restoreLiquidGlassMinimizeBehaviorIfNeeded()
            if usesModernPadBottomTabMenu {
                ensureModernPadFullWidthTabPlatterIfNeeded()
                applyModernPadBottomBarLayoutIfNeeded()
                ensureModernPadHostedSearchOrderIfNeeded()
                if transientPadSelectedTabTitle != nil {
                    syncModernPadSelectedTabVisualsIfNeeded()
                }
            }
            if usesFloatingQueueCardOnPhone,
               let sourcesRootController = sileoViewControllers?[safe: 2] {
                sourcesViewController(in: sourcesRootController)?.layoutSourceRefreshIndicatorIfNeeded()
            }
        } else if usesFloatingQueueCardOnPhone {
            configurePopupTapIfNeeded()
        }
        if #unavailable(iOS 26.0), UIDevice.current.userInterfaceIdiom == .pad {
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
        if !(usesModernPadBottomTabMenu && isModernPadSearchActive) {
            setBottomAccessory(UITabAccessory(contentView: queueBar), animated: false)
        }
        if usesFloatingQueueCardOnPhone {
            // accessory 加入后可能重建观察关系，不能依赖后续滚动中的重复设置来恢复。
            registerLiquidGlassContentScrollView()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.popupIsPresented,
                      !self.isQueueSheetVisible, !self.isPresentingQueueSheet else { return }
                self.registerLiquidGlassContentScrollView()
            }
        } else if usesModernPadBottomTabMenu {
            (sileoSelectedViewController as? SourcesSplitViewController)?.padScrollCoordinator?.markNeedsRebind()
        }
    }

    @available(iOS 26.0, *)
    private func restoreLiquidGlassQueueBarIfNeeded(animated: Bool) {
        guard usesModernPadBottomTabMenu,
              popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              !isModernPadSearchActive,
              bottomAccessory == nil else {
            return
        }
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
        setBottomAccessory(UITabAccessory(contentView: queueBar), animated: animated)
        restoreLiquidGlassMinimizeBehaviorIfNeeded()
        (sileoSelectedViewController as? SourcesSplitViewController)?.padScrollCoordinator?.markNeedsRebind()
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
        } else if usesModernPadBottomTabMenu {
            updateLiquidGlassTabBarMinimizeBehavior()
            ensureModernPadFullWidthTabPlatterIfNeeded()
        }
    }

    // MARK: - iPadOS 26+ Bottom Tab Dual-Column Scroll & Back-to-Top Expand

    @available(iOS 26.0, *)
    private var activeModernPadSourcesSplit: SourcesSplitViewController? {
        guard usesModernPadBottomTabMenu,
              let split = sileoSelectedViewController as? SourcesSplitViewController,
              split.style != .unspecified else {
            return nil
        }
        return split
    }

    private func modernPadScrollState(for scrollView: UIScrollView) -> ModernPadScrollState {
        if let existing = modernPadScrollStates.object(forKey: scrollView) {
            return existing
        }
        let created = ModernPadScrollState()
        modernPadScrollStates.setObject(created, forKey: scrollView)
        return created
    }

    @available(iOS 26.0, *)
    private func isScrollViewAllowedForModernPadExpand(_ scrollView: UIScrollView) -> Bool {
        if let split = activeModernPadSourcesSplit, split.containsColumnScrollView(scrollView) {
            return split.padScrollCoordinator?.isActive(scrollView) ?? true
        }
        return true
    }

    @available(iOS 26.0, *)
    func handleModernPadHitTest(_ hitView: UIView) {
        guard usesModernPadBottomTabMenu,
              popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              let split = activeModernPadSourcesSplit else {
            return
        }
        split.activateColumnScrollView(containing: hitView)
    }

    func handleModernPadScrollDidChangeAdjustedInset(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *), usesModernPadBottomTabMenu else { return }
        let state = modernPadScrollState(for: scrollView)
        let cur = scrollView.adjustedContentInset
        if state.hasRecordedInset,
           abs(cur.top - state.lastAdjustedInset.top) > 1 || abs(cur.bottom - state.lastAdjustedInset.bottom) > 1 {
            if let split = activeModernPadSourcesSplit, split.containsColumnScrollView(scrollView) {
                // 任意一栏的 top（大标题缩放）或 bottom（底栏收起/展开）安全区变化，
                // 都可能让右栏 UINavigationController 抢走底栏观测，标记下次交互前重绑。
                split.padScrollCoordinator?.markNeedsRebind(from: scrollView)
            }
        }
        state.lastAdjustedInset = cur
        state.hasRecordedInset = true
    }

    func handleModernPadScrollWillBeginDragging(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *), usesModernPadBottomTabMenu else { return }
        let state = modernPadScrollState(for: scrollView)
        state.didExpandOnCurrentTopGesture = false
        state.lastScrollOffsetY = scrollView.contentOffset.y
        state.lastScrollDeltaY = 0
        guard popupIsPresented, !isQueueSheetEffectivelyVisible, !isPresentingQueueSheet else { return }
        restoreLiquidGlassMinimizeBehaviorIfNeeded()
        if let split = activeModernPadSourcesSplit, split.containsColumnScrollView(scrollView) {
            split.padScrollCoordinator?.activate(scrollView, forceRebind: false)
        }
    }

    func handleModernPadScrollShouldScrollToTop(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *), usesModernPadBottomTabMenu else { return }
        let state = modernPadScrollState(for: scrollView)
        state.didExpandOnCurrentTopGesture = false
        guard popupIsPresented, !isQueueSheetEffectivelyVisible, !isPresentingQueueSheet else { return }
        if let split = activeModernPadSourcesSplit, split.containsColumnScrollView(scrollView) {
            split.padScrollCoordinator?.activate(scrollView, forceRebind: true)
        }
    }

    func handleModernPadScrollDidScrollToTop(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *), usesModernPadBottomTabMenu else { return }
        let state = modernPadScrollState(for: scrollView)
        state.hasScrolledBelowTop = false
        guard popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              isScrollViewAllowedForModernPadExpand(scrollView) else {
            return
        }
        expandModernPadTabBarIfNeeded()
    }

    func handleModernPadScrollDidScroll(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *), usesModernPadBottomTabMenu else { return }
        let state = modernPadScrollState(for: scrollView)
        let topY = -scrollView.adjustedContentInset.top
        let y = scrollView.contentOffset.y
        let deltaY = y - state.lastScrollOffsetY
        state.lastScrollOffsetY = y
        if deltaY != 0 {
            state.lastScrollDeltaY = deltaY
        }

        // 仅在用户主动拖拽或惯性滚动当前列表时才做回顶恢复判定，
        // 绝不在另一栏触发底栏收缩导致本栏 inset 微调时误触发回顶展开。
        guard popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              scrollView.isDragging || scrollView.isDecelerating,
              isScrollViewAllowedForModernPadExpand(scrollView) else {
            return
        }

        if y > topY + 24 {
            state.hasScrolledBelowTop = true
            state.didExpandOnCurrentTopGesture = false
            return
        }

        // 1) 从下方滑回顶部（快滑、慢滑、惯性滑回顶部）
        if state.hasScrolledBelowTop && deltaY < 0 && y <= topY + 2 {
            state.hasScrolledBelowTop = false
            state.didExpandOnCurrentTopGesture = true
            expandModernPadTabBarIfNeeded()
            return
        }

        // 2) 本身已在顶部时，用户继续下拉回弹也立即恢复展开态（例如另一栏曾触发收缩）
        if scrollView.isDragging && !state.didExpandOnCurrentTopGesture && y < topY - 12 {
            state.didExpandOnCurrentTopGesture = true
            expandModernPadTabBarIfNeeded()
        }
    }

    func handleModernPadScrollDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard #available(iOS 26.0, *),
              usesModernPadBottomTabMenu,
              popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              !decelerate,
              isScrollViewAllowedForModernPadExpand(scrollView) else {
            return
        }
        let state = modernPadScrollState(for: scrollView)
        let topY = -scrollView.adjustedContentInset.top
        if state.hasScrolledBelowTop && state.lastScrollDeltaY <= 0 && scrollView.contentOffset.y <= topY + 2 {
            state.hasScrolledBelowTop = false
            if !state.didExpandOnCurrentTopGesture {
                state.didExpandOnCurrentTopGesture = true
                expandModernPadTabBarIfNeeded()
            }
        }
    }

    func handleModernPadScrollDidEndDecelerating(_ scrollView: UIScrollView) {
        guard #available(iOS 26.0, *),
              usesModernPadBottomTabMenu,
              popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              isScrollViewAllowedForModernPadExpand(scrollView) else {
            return
        }
        let state = modernPadScrollState(for: scrollView)
        let topY = -scrollView.adjustedContentInset.top
        if state.hasScrolledBelowTop && state.lastScrollDeltaY <= 0 && scrollView.contentOffset.y <= topY + 2 {
            state.hasScrolledBelowTop = false
            if !state.didExpandOnCurrentTopGesture {
                state.didExpandOnCurrentTopGesture = true
                expandModernPadTabBarIfNeeded()
            }
        }
    }

    @available(iOS 26.0, *)
    private func expandModernPadTabBarIfNeeded() {
        guard usesModernPadBottomTabMenu,
              popupIsPresented,
              !isQueueSheetEffectivelyVisible,
              !isPresentingQueueSheet,
              tabBarMinimizeBehavior == .onScrollDown else {
            return
        }
        if let morphTarget = currentLiquidGlassMorphTarget(), morphTarget != 2 {
            return
        }
        activeModernPadSourcesSplit?.padScrollCoordinator?.markNeedsRebind()
        UIView.animate(withDuration: 0.25) {
            self.tabBarMinimizeBehavior = .never
            self.view.layoutIfNeeded()
        }
        tabBarMinimizeBehavior = .onScrollDown
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
    private var usesCompactFonts = false

    override init(frame: CGRect) {
        glassView = UIVisualEffectView(effect: SileoGlass.effect(interactive: true,
                                                                 tintColor: UIColor.sileoBackgroundColor.withAlphaComponent(0.18)))
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = true
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        glassView.isUserInteractionEnabled = false
        glassView.clipsToBounds = true
        glassView.layer.cornerCurve = .continuous
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
        // 文字按顺序添加在玻璃上方，并固定 zPosition，布局时无需重复重排。

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
        if glassView.frame != bounds {
            glassView.frame = bounds
        }
        let cornerRadius = min(bounds.width, bounds.height) / 2
        if layer.cornerRadius != cornerRadius {
            layer.cornerRadius = cornerRadius
        }
        if glassView.layer.cornerRadius != cornerRadius {
            glassView.layer.cornerRadius = cornerRadius
        }
        let isInlineEnvironment: Bool
        if #available(iOS 26.0, *) {
            isInlineEnvironment = traitCollection.tabAccessoryEnvironment == .inline
        } else {
            isInlineEnvironment = false
        }
        let isCompactHeight = isInlineEnvironment || bounds.height < 56
        if usesCompactFonts != isCompactHeight {
            usesCompactFonts = isCompactHeight
            titleLabel.font = UIFont.systemFont(ofSize: isCompactHeight ? 12 : 13,
                                                 weight: .regular)
            subtitleLabel.font = UIFont.systemFont(ofSize: isCompactHeight ? 16 : 17,
                                                    weight: .semibold)
        }
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

private final class ModernPadScrollState {
    var lastScrollOffsetY: CGFloat = 0
    var lastScrollDeltaY: CGFloat = 0
    var lastAdjustedInset: UIEdgeInsets = .zero
    var hasRecordedInset = false
    var hasScrolledBelowTop = false
    var didExpandOnCurrentTopGesture = false
}

private final class ModernBadgeDisplayTick: NSObject {
    private weak var owner: TabBarController?

    init(owner: TabBarController) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.updateModernTabBadges()
    }
}

// 新标签 API 不维护旧的数组与选择属性，业务入口统一通过这些访问器定位页面。
extension UITabBarController {
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
            if #available(iOS 18.0, *), !tabs.isEmpty {
                selectedTab = tabs.first { $0.viewController === newValue }
            } else {
                selectedViewController = newValue
            }
            (self as? TabBarController)?.handleProgrammaticTabSelection()
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
                selectedTab = tabs[newValue]
            } else {
                selectedIndex = newValue
            }
            (self as? TabBarController)?.handleProgrammaticTabSelection()
        }
    }
}

extension UIViewController {
    func setSileoTabBadgeValue(_ value: String?) {
        // iOS / iPadOS 26+ 统一由 TabBarController 按稳定 Tab 标识同步原生 badgeValue 与角标渲染器。
        if #available(iOS 26.0, *),
           (UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad),
           let controller = (tabBarController as? TabBarController) ?? TabBarController.singleton,
           controller.setTabBadgeValue(value, for: self) {
            return
        }
        tabBarItem.badgeValue = value
        if #available(iOS 18.0, *) {
            tab?.badgeValue = value
        }
    }
}
