//
//  TabBar.swift
//  Sileo
//
//  Created by CoolStar on 7/27/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

class TabBar: UITabBar {
    var onLayoutSubviews: (() -> Void)?
    var onDidMoveToWindow: (() -> Void)?
    var onDidAddSubview: ((UIView) -> Void)?
    var onWillRemoveSubview: ((UIView) -> Void)?
    var modernPadWidthRatio: CGFloat?

    private var isAdjustingModernPadGeometry = false

    private func modernPadTargetWidth(for containerWidth: CGFloat) -> CGFloat? {
        guard #available(iOS 26.0, *),
              UIDevice.current.userInterfaceIdiom == .pad,
              let ratio = modernPadWidthRatio,
              ratio > 0, ratio < 1,
              containerWidth > 0 else {
            return nil
        }
        // 按屏幕/窗口宽度的指定比例居中显示；窄分屏下保留 350pt 最小可用宽度，避免四标签与搜索键重叠。
        // iPadOS 26 的浮动底栏主托盘上限约 336pt、横屏搜索框上限约 316.5pt，限制最大宽度 396pt 可彻底避免中间出现空洞；
        // iPadOS 27 支持主托盘与搜索框随底栏宽度完整铺满，直接按 50% 宽度显示。
        var desired = max(350, floor(containerWidth * ratio))
        if #unavailable(iOS 27.0) {
            desired = min(desired, 396)
        }
        let target = min(containerWidth, desired)
        return target < containerWidth - 1 ? target : nil
    }

    func refreshModernPadFrameIfNeeded() {
        let current = super.frame
        guard current.width > 0 else { return }
        let containerWidth = superview?.bounds.width ?? window?.bounds.width ?? current.width
        guard let targetWidth = modernPadTargetWidth(for: containerWidth) else { return }
        let targetX = floor((containerWidth - targetWidth) / 2)
        if abs(current.width - targetWidth) > 0.5 || abs(current.origin.x - targetX) > 0.5 {
            isAdjustingModernPadGeometry = true
            super.frame = CGRect(x: targetX, y: current.origin.y, width: targetWidth, height: current.height)
            isAdjustingModernPadGeometry = false
        }
    }

    override var frame: CGRect {
        get { super.frame }
        set {
            guard !isAdjustingModernPadGeometry,
                  newValue.width > 0 else {
                super.frame = newValue
                return
            }
            let containerWidth = superview?.bounds.width ?? window?.bounds.width ?? newValue.width
            guard let targetWidth = modernPadTargetWidth(for: containerWidth),
                  newValue.width > targetWidth + 0.5 else {
                super.frame = newValue
                return
            }
            let horizontalInset = floor((newValue.width - targetWidth) / 2)
            isAdjustingModernPadGeometry = true
            super.frame = CGRect(x: newValue.origin.x + horizontalInset,
                                 y: newValue.origin.y,
                                 width: targetWidth,
                                 height: newValue.height)
            isAdjustingModernPadGeometry = false
        }
    }

    override var bounds: CGRect {
        get { super.bounds }
        set {
            guard !isAdjustingModernPadGeometry,
                  newValue.width > 0 else {
                super.bounds = newValue
                return
            }
            let containerWidth = superview?.bounds.width ?? window?.bounds.width ?? newValue.width
            guard let targetWidth = modernPadTargetWidth(for: containerWidth),
                  newValue.width > targetWidth + 0.5 else {
                super.bounds = newValue
                return
            }
            isAdjustingModernPadGeometry = true
            super.bounds = CGRect(origin: newValue.origin,
                                  size: CGSize(width: targetWidth, height: newValue.height))
            isAdjustingModernPadGeometry = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onDidMoveToWindow?()
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        onDidAddSubview?(subview)
    }

    override func willRemoveSubview(_ subview: UIView) {
        onWillRemoveSubview?(subview)
        super.willRemoveSubview(subview)
    }

    override var traitCollection: UITraitCollection {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return super.traitCollection
        }
        if #available(iOS 26.0, *) {
            return super.traitCollection
        }
        if UIApplication.shared.statusBarOrientation.isLandscape && self.bounds.width >= 400 {
            return super.traitCollection
        }
        return UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(horizontalSizeClass: .compact)])
    }
}

/// 承载软件源刷新转圈的角标视图。iOS 27 与原生回退模式下挂在系统 `_UIBarBadgeView` 内部。
final class RefreshBadge: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(usesNativeBackground: Bool = false) {
        super.init(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        if !usesNativeBackground {
            backgroundColor = .systemRed
            layer.cornerRadius = 10
        }
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "Sileo.SourceRefreshBadge"
        spinner.color = .white
        spinner.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
        spinner.isUserInteractionEnabled = false
        spinner.accessibilityIdentifier = "Sileo.SourceRefreshIndicator"
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        addSubview(spinner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func start() {
        if !spinner.isAnimating {
            spinner.startAnimating()
        }
    }

    func stop() {
        if spinner.isAnimating {
            spinner.stopAnimating()
        }
    }
}

/// iOS 27 与原生回退路径下，把白色转圈挂到系统生成的 `_UIBarBadgeView` 内。
@MainActor
final class NativeRefreshBadge {
    // 数字等宽空格保留原生单数字红圈的尺寸，留出中间位置绘制转圈。
    static let value = "\u{2007}"

    func update(in view: UIView, isRefreshing: Bool) {
        if isNativeBadgeView(view) {
            updateSpinner(in: view, isRefreshing: isRefreshing)
            return
        }
        for subview in view.subviews {
            update(in: subview, isRefreshing: isRefreshing)
        }
    }

    private func isNativeBadgeView(_ view: UIView) -> Bool {
        let className = NSStringFromClass(type(of: view))
        if className == "_UIBarBadgeView" {
            return true
        }
        // 回退匹配：若未来小版本调整了内部角标类名，仅对不含子角标的叶子角标视图匹配占位符。
        guard className.localizedCaseInsensitiveContains("Badge"),
              !className.localizedCaseInsensitiveContains("Container"),
              max(view.bounds.width, view.bounds.height) <= 44,
              !view.subviews.contains(where: { NSStringFromClass(type(of: $0)).localizedCaseInsensitiveContains("Badge") }) else {
            return false
        }
        return view.subviews.contains { ($0 as? UILabel)?.text == Self.value }
            || view.subviews.contains { $0 is RefreshBadge }
    }

    private func updateSpinner(in badge: UIView, isRefreshing: Bool) {
        let existing = badge.subviews.compactMap { $0 as? RefreshBadge }
        let isSource = isRefreshing && badge.subviews.contains { ($0 as? UILabel)?.text == Self.value }
        guard isSource else {
            for spinner in existing {
                spinner.stop()
                spinner.removeFromSuperview()
            }
            return
        }
        if let spinner = existing.first {
            // 清理意外重复挂载的实例，并在切回前台或复用后确保转圈持续动画。
            for duplicate in existing.dropFirst() {
                duplicate.stop()
                duplicate.removeFromSuperview()
            }
            if spinner.frame != badge.bounds {
                spinner.frame = badge.bounds
                spinner.setNeedsLayout()
                spinner.layoutIfNeeded()
            }
            if badge.subviews.last !== spinner {
                badge.bringSubviewToFront(spinner)
            }
            spinner.start()
            return
        }

        // 标签栏过渡会创建新的原生角标视图。转圈随角标自身的层级移动。
        let refresh = RefreshBadge(usesNativeBackground: true)
        refresh.frame = badge.bounds
        refresh.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        badge.addSubview(refresh)
        refresh.setNeedsLayout()
        refresh.layoutIfNeeded()
        refresh.start()
    }
}

/// iOS 27 标签切换期间，UIKit 会把液态玻璃透镜临时提升为 `UITabBar` 的顶层 `_UIPortalView` 兄弟视图，
/// 使位于 `_UITabBarItemPlatterView` 内部的原生 `BadgeContainerView` 在切换与落位瞬间被透镜盖住。
/// 此辅助器仅在透镜 `_UIPortalView` 活跃且未进入收展/搜索形变时，用系统同款 `CAPortalLayer`
/// （通过 `matchesPosition`/`matchesTransform`/`matchesOpacity` 自动镜像，不使用任何手动坐标或偏移）
/// 将原生角标容器提升到透镜之上；透镜移除或进入其他过渡时立刻同步卸载并恢复原生绘制。
@MainActor
final class NativeBadgePortalLift {
    private typealias SetLayerIMP = @convention(c) (AnyObject, Selector, CALayer?) -> Void
    private typealias SetBoolIMP = @convention(c) (AnyObject, Selector, ObjCBool) -> Void

    private static let portalViewClassName = "_UIPortalView"
    private static let sourceViewSelector = NSSelectorFromString("sourceView")
    private static let setSourceLayerSelector = NSSelectorFromString("setSourceLayer:")
    private static let setHidesSourceLayerSelector = NSSelectorFromString("setHidesSourceLayer:")
    private static let setMatchesPositionSelector = NSSelectorFromString("setMatchesPosition:")
    private static let setMatchesTransformSelector = NSSelectorFromString("setMatchesTransform:")
    private static let setMatchesOpacitySelector = NSSelectorFromString("setMatchesOpacity:")

    private var portalLayer: CALayer?
    private weak var currentSourceLayer: CALayer?
    private(set) var isActive = false

    func update(in tabBar: UITabBar, excluding removingSubview: UIView? = nil) {
        guard tabBar.window != nil, !tabBar.isHidden else {
            deactivate()
            return
        }

        let activeSubviews = tabBar.subviews.filter { $0 !== removingSubview }

        // 正在进行收起/展开/搜索形变过渡时，绝不接管原生角标绘制。
        let hasMorphTransition = activeSubviews.contains { subview in
            let cls = NSStringFromClass(type(of: subview))
            return cls.contains("Reparenting") || cls.contains("MagicMorph")
        }
        guard !hasMorphTransition else {
            deactivate()
            return
        }

        // 仅在系统为液态玻璃透镜插入顶层 `_UIPortalView` 时激活镜像提升。
        guard let lensPortal = activeSubviews.first(where: isLiquidLensPortal) else {
            deactivate()
            return
        }

        // 紧凑托盘与展开托盘同时可见时处于收展/搜索切换中，立即退出提升。
        let hasVisibleCompactPlatter = activeSubviews.contains { subview in
            let cls = NSStringFromClass(type(of: subview))
            return cls.contains("PlatterView")
                && !cls.contains("ItemPlatterView")
                && !subview.isHidden
                && subview.alpha > 0.01
        }
        guard !hasVisibleCompactPlatter else {
            deactivate()
            return
        }

        guard let expandedPlatter = activeSubviews.first(where: { subview in
            NSStringFromClass(type(of: subview)).contains("_UITabBarItemPlatterView")
                && !subview.isHidden
                && subview.alpha > 0.01
        }) else {
            deactivate()
            return
        }

        guard let badgeContainer = expandedPlatter.subviews.first(where: { subview in
            NSStringFromClass(type(of: subview)).contains("BadgeContainerView")
                && !subview.isHidden
                && subview.alpha > 0.01
        }) else {
            deactivate()
            return
        }

        let hasVisibleBadge = badgeContainer.subviews.contains { !$0.isHidden && $0.alpha > 0.01 }
        guard hasVisibleBadge else {
            deactivate()
            return
        }

        activate(sourceLayer: badgeContainer.layer, above: lensPortal.layer, in: tabBar.layer)
    }

    func deactivate() {
        guard let portal = portalLayer else {
            currentSourceLayer = nil
            isActive = false
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setBool(portal, selector: Self.setHidesSourceLayerSelector, value: false)
        setLayer(portal, selector: Self.setSourceLayerSelector, value: nil)
        portal.isHidden = true
        portal.removeFromSuperlayer()
        CATransaction.commit()
        currentSourceLayer = nil
        isActive = false
    }

    private func activate(sourceLayer: CALayer, above lensLayer: CALayer, in hostLayer: CALayer) {
        guard let portal = ensurePortalLayer() else { return }
        let targetZ = max(lensLayer.zPosition, 0) + 1

        if isActive,
           currentSourceLayer === sourceLayer,
           portal.superlayer === hostLayer,
           portal.zPosition == targetZ,
           !portal.isHidden {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if currentSourceLayer !== sourceLayer {
            setBool(portal, selector: Self.setHidesSourceLayerSelector, value: false)
            setLayer(portal, selector: Self.setSourceLayerSelector, value: sourceLayer)
            currentSourceLayer = sourceLayer
        }
        setBool(portal, selector: Self.setMatchesPositionSelector, value: true)
        setBool(portal, selector: Self.setMatchesTransformSelector, value: true)
        setBool(portal, selector: Self.setMatchesOpacitySelector, value: true)
        setBool(portal, selector: Self.setHidesSourceLayerSelector, value: true)
        portal.zPosition = targetZ
        portal.isHidden = false
        if portal.superlayer !== hostLayer {
            hostLayer.addSublayer(portal)
        }
        CATransaction.commit()
        isActive = true
    }

    private func ensurePortalLayer() -> CALayer? {
        if let portalLayer {
            return portalLayer
        }
        guard let portalClass = NSClassFromString("CAPortalLayer") as? CALayer.Type else {
            return nil
        }
        let layer = portalClass.init()
        guard layer.responds(to: Self.setSourceLayerSelector),
              layer.responds(to: Self.setHidesSourceLayerSelector),
              layer.responds(to: Self.setMatchesPositionSelector),
              layer.responds(to: Self.setMatchesTransformSelector),
              layer.responds(to: Self.setMatchesOpacitySelector) else {
            return nil
        }
        layer.name = "Sileo.NativeBadgePortalLift"
        layer.allowsEdgeAntialiasing = true
        portalLayer = layer
        return layer
    }

    private func isLiquidLensPortal(_ view: UIView) -> Bool {
        guard NSStringFromClass(type(of: view)) == Self.portalViewClassName,
              !view.isHidden,
              view.responds(to: Self.sourceViewSelector),
              let sourceView = view.perform(Self.sourceViewSelector)?.takeUnretainedValue() as? UIView,
              let sourceSuperview = sourceView.superview else {
            return false
        }
        return NSStringFromClass(type(of: sourceSuperview)).contains("LiquidLens")
    }

    private func setLayer(_ target: CALayer, selector: Selector, value: CALayer?) {
        guard target.responds(to: selector) else { return }
        let imp = target.method(for: selector)
        let fn = unsafeBitCast(imp, to: SetLayerIMP.self)
        fn(target, selector, value)
    }

    private func setBool(_ target: CALayer, selector: Selector, value: Bool) {
        guard target.responds(to: selector) else { return }
        let imp = target.method(for: selector)
        let fn = unsafeBitCast(imp, to: SetBoolIMP.self)
        fn(target, selector, ObjCBool(value))
    }
}

/// iOS 26 专用锚点角标渲染器（基于独立 Demo 第 34 号验收基线）。
/// 保留原生 `UITab.badgeValue` 供 UIKit 生成定位视图，通过透明外观隐藏原生绘制，
/// 在应用窗口宿主层以单图层栅格化绘制红圈、数字胶囊和转圈动画；若内部层级不匹配则回退原生角标。
@MainActor
final class AnchoredBadgeRenderer {
    private enum Kind: Hashable { case refresh, count }

    private final class Marker: UIView {
        var kind: Kind

        init(kind: Kind, frame: CGRect) {
            self.kind = kind
            super.init(frame: frame)
            isOpaque = false
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            accessibilityIdentifier = "Sileo.BadgeAnchor"
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private struct Track {
        let kind: Kind
        let marker: Marker
        let source: UIView
        let portal: UIView?
        let motionView: UIView?
        let viewport: UIView?
        let visibilityRoot: UIView
        var referencePlatter: UIView? = nil
    }

    private struct Placement {
        let frame: CGRect
        let alpha: CGFloat
    }

    private struct MotionKey: Hashable {
        let kind: Kind
        let view: ObjectIdentifier
    }

    private struct MotionPlacement {
        var strongest: Placement
        var combinedAlpha: CGFloat
        let groupAlpha: CGFloat
    }

    private struct RefreshArtworkKey: Equatable {
        let color: CGColor
        let scale: CGFloat
        let interfaceStyle: UIUserInterfaceStyle
        let contrast: UIAccessibilityContrast
    }

    private struct CountArtworkKey: Equatable {
        let text: String
        let color: CGColor
        let scale: CGFloat
        let interfaceStyle: UIUserInterfaceStyle
        let contrast: UIAccessibilityContrast
    }

    private static let portalClass = "_UIPortalView"
    private static let sourceSelector = NSSelectorFromString("sourceView")
    private static let diameter: CGFloat = 18 + 1 / 3
    private static let fallbackGraceDuration: CFTimeInterval = 0.75
    private static let countTextAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13),
        .foregroundColor: UIColor.white
    ]

    private let host = UIView()
    private weak var hostView: UIView?
    private weak var attachedWindow: UIWindow?
    private var lastWindowBounds: CGRect = .zero
    private let refresh = CALayer()
    private let count = CALayer()
    private let fallbackRefreshBadge = NativeRefreshBadge()

    private var isRefreshing: Bool
    private var countValue: String?
    private var countBadgeColor: UIColor?

    private var originalStandardAppearance: UITabBarAppearance
    private var originalScrollEdgeAppearance: UITabBarAppearance?
    private(set) var isUsingNativeFallback = false
    private var mismatchStartTime: CFTimeInterval?

    private var refreshArtworkKey: RefreshArtworkKey?
    private var refreshFrames: [CGImage] = []
    private var countArtworkKey: CountArtworkKey?

    private var topology: [ObjectIdentifier] = []
    private var directTracks: [Track] = []
    private var transitionTracks: [Track] = []
    private var transitionRootIDs: Set<ObjectIdentifier> = []
    private var outgoingTracks: [Kind: Track] = [:]
    private var needsDiscovery = true

    var hasActiveBadges: Bool {
        isRefreshing || countValue != nil
    }

    var needsDisplayUpdates: Bool {
        if isUsingNativeFallback {
            return isRefreshing
        }
        return hasActiveBadges
    }

    var needsHighFrameRate: Bool {
        !isUsingNativeFallback && hasActiveBadges
    }

    init(tabBar: UITabBar,
         hostView: UIView,
         isRefreshing: Bool,
         countValue: String?,
         countBadgeColor: UIColor? = nil) {
        self.hostView = hostView
        self.isRefreshing = isRefreshing
        self.countValue = countValue.flatMap { $0.isEmpty ? nil : $0 }
        self.countBadgeColor = countBadgeColor
        self.originalStandardAppearance = tabBar.standardAppearance.copy()
        self.originalScrollEdgeAppearance = tabBar.scrollEdgeAppearance?.copy()

        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.isUserInteractionEnabled = false
        host.accessibilityElementsHidden = true
        host.accessibilityIdentifier = "Sileo.AnchoredBadgeHost"
        refresh.name = "Sileo.RasterRefreshBadge"
        count.name = "Sileo.RasterPackageBadge"
        for layer in [refresh, count] {
            layer.isHidden = true
            host.layer.addSublayer(layer)
        }

        applyCurrentAppearances(to: tabBar)
    }

    func setRefreshing(_ refreshing: Bool, in tabBar: UITabBar) {
        guard isRefreshing != refreshing else { return }
        isRefreshing = refreshing
        mismatchStartTime = nil
        if !refreshing {
            outgoingTracks[.refresh] = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            refresh.isHidden = true
            refresh.removeAnimation(forKey: "refreshRotation")
            CATransaction.commit()
            if isUsingNativeFallback {
                fallbackRefreshBadge.update(in: tabBar, isRefreshing: false)
            }
        }
        invalidateLayout()
    }

    func setCount(_ value: String?, badgeColor: UIColor?, in tabBar: UITabBar) {
        let normalized = value.flatMap { $0.isEmpty ? nil : $0 }
        guard countValue != normalized || countBadgeColor != badgeColor else { return }
        countValue = normalized
        countBadgeColor = badgeColor
        mismatchStartTime = nil
        if normalized == nil {
            outgoingTracks[.count] = nil
            countArtworkKey = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            count.isHidden = true
            count.contents = nil
            CATransaction.commit()
        }
        invalidateLayout()
    }

    func updateBaseAppearances(in tabBar: UITabBar, transform: (UITabBarAppearance) -> UITabBarAppearance) {
        originalStandardAppearance = transform(originalStandardAppearance)
        if let scrollEdge = originalScrollEdgeAppearance {
            originalScrollEdgeAppearance = transform(scrollEdge)
        }
        applyCurrentAppearances(to: tabBar)
    }

    func invalidateLayout() {
        needsDiscovery = true
    }

    func detach() {
        attachedWindow = nil
        lastWindowBounds = .zero
        mismatchStartTime = nil
        resetTracks()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refresh.isHidden = true
        count.isHidden = true
        CATransaction.commit()
        host.removeFromSuperview()
    }

    func teardown(restoring tabBar: UITabBar?) {
        detach()
        refresh.removeAnimation(forKey: "refreshRotation")
        if let tabBar {
            removeAllMarkers(in: tabBar)
            restoreOriginalAppearances(to: tabBar)
        }
    }

    func update(in tabBar: UITabBar,
                isSearchTabSelected: Bool,
                selectedPrimaryIsSources: Bool,
                selectedPrimaryIsPackages: Bool) {
        guard let window = hostView?.window, tabBar.window === window else {
            detach()
            return
        }

        if isUsingNativeFallback {
            if attachedWindow !== window {
                // 窗口迁移后允许在新窗口环境重新评估。
                attachedWindow = window
                lastWindowBounds = window.bounds
                isUsingNativeFallback = false
                mismatchStartTime = nil
                resetTracks()
                applyCurrentAppearances(to: tabBar)
            } else {
                fallbackRefreshBadge.update(in: tabBar, isRefreshing: isRefreshing)
                return
            }
        }

        if attachedWindow !== window || lastWindowBounds != window.bounds {
            attachedWindow = window
            lastWindowBounds = window.bounds
            mismatchStartTime = nil
            resetTracks()
            host.frame = window.bounds
            if host.superview !== window {
                window.addSubview(host)
            }
        } else if host.superview !== window {
            // 角标在窗口的展示层绘制，避开标签控制器临时提升过渡视图的层级。
            host.frame = window.bounds
            window.addSubview(host)
        }

        guard hasActiveBadges else {
            mismatchStartTime = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if !refresh.isHidden { refresh.isHidden = true }
            if !count.isHidden { count.isHidden = true }
            if refresh.animation(forKey: "refreshRotation") != nil {
                refresh.removeAnimation(forKey: "refreshRotation")
            }
            CATransaction.commit()
            outgoingTracks.removeAll(keepingCapacity: true)
            return
        }

        let branches = tabBar.subviews
        let branchChildren = branches.flatMap(\.subviews)
        let candidates = branchChildren.compactMap { portal -> (portal: UIView, root: UIView)? in
            guard let source = portalSource(portal) else { return nil }
            return (portal, source)
        }
        var distinctRoots: Set<ObjectIdentifier> = []
        let candidateRoots = candidates.map(\.root).filter { distinctRoots.insert(ObjectIdentifier($0)).inserted }
        let current = (branches + branchChildren + candidateRoots + candidateRoots.flatMap(\.subviews))
            .map(ObjectIdentifier.init)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let layoutChanged = needsDiscovery || topology != current
        let missingDirectActive =
            (isRefreshing && !directTracks.contains(where: { $0.kind == .refresh })) ||
            (countValue != nil && !directTracks.contains(where: { $0.kind == .count }))
        let needsDirectDiscovery = layoutChanged || missingDirectActive
        // 系统可能先插入 Portal，再填入动画树；或动画中新增角标。过渡未覆盖当前活跃角标时重新检查候选视图。
        let missingTransitionActive = !candidates.isEmpty && (
            transitionRootIDs.isEmpty ||
            (isRefreshing && !transitionTracks.contains(where: { $0.kind == .refresh })) ||
            (countValue != nil && !transitionTracks.contains(where: { $0.kind == .count }))
        )
        let needsTransitionDiscovery = layoutChanged || missingTransitionActive

        let platters = branches.filter(isPlatter)
        if needsDirectDiscovery {
            topology = current
            needsDiscovery = false
            directTracks = platters.flatMap { platter in
                markers(in: platter).compactMap { marker in
                    guard let icon = marker.superview else { return nil }
                    return Track(kind: marker.kind, marker: marker, source: icon, portal: nil, motionView: nil,
                                 viewport: nil, visibilityRoot: tabBar, referencePlatter: platter)
                }
            }
        }
        if needsTransitionDiscovery {
            transitionRootIDs.removeAll(keepingCapacity: true)
            transitionTracks.removeAll(keepingCapacity: true)
            for root in candidateRoots {
                guard let tracks = tracks(in: root) else { continue }
                transitionRootIDs.insert(ObjectIdentifier(root))
                transitionTracks.append(contentsOf: tracks)
            }
        }
        let presenters = candidates.filter { transitionRootIDs.contains(ObjectIdentifier($0.root)) }
        let hasCoveringModal = positionHost(in: window)
        if host.isHidden != tabBar.isHidden { host.isHidden = tabBar.isHidden }

        // 每帧只读取缓存的图标、过渡层和它们的坐标。显示树改变时才重新查找。
        var placements: [Kind: Placement] = [:]
        var waitingForPresentation: Set<Kind> = []
        var ready: Set<Kind> = []
        if presenters.isEmpty {
            outgoingTracks.removeAll(keepingCapacity: true)
            for track in directTracks where isActive(track.kind) && placements[track.kind] == nil {
                if let position = placement(for: track, window: window) {
                    placements[track.kind] = position
                    outgoingTracks[track.kind] = track
                }
            }
        } else {
            var motionPlacements: [MotionKey: MotionPlacement] = [:]
            for track in transitionTracks where isActive(track.kind) {
                guard let portal = track.portal, portal.window === window else { continue }
                if let visible = portal.layer.presentation() {
                    ready.insert(track.kind)
                    guard let position = placement(for: track, window: window, view: portal, layer: visible) else { continue }
                    if let motion = track.motionView {
                        let key = MotionKey(kind: track.kind, view: ObjectIdentifier(motion))
                        if var group = motionPlacements[key] {
                            if position.alpha > group.strongest.alpha { group.strongest = position }
                            group.combinedAlpha += position.alpha
                            motionPlacements[key] = group
                        } else {
                            motionPlacements[key] = MotionPlacement(
                                strongest: position,
                                combinedAlpha: position.alpha,
                                groupAlpha: opacity(of: motion, through: track.visibilityRoot)
                            )
                        }
                    } else if position.alpha > (placements[track.kind]?.alpha ?? -1) {
                        placements[track.kind] = position
                    }
                } else if let motion = track.motionView, let layer = motion.layer.presentation(),
                          let position = placement(for: track, window: window, view: motion, layer: layer) {
                    if position.alpha > (placements[track.kind]?.alpha ?? -1) { placements[track.kind] = position }
                } else {
                    waitingForPresentation.insert(track.kind)
                }
            }
            // 同一个动画视图交叉淡化图标副本。角标使用整组图标的可见度。
            for (key, group) in motionPlacements {
                let alpha = min(group.groupAlpha, group.combinedAlpha)
                if alpha > (placements[key.kind]?.alpha ?? -1) {
                    placements[key.kind] = Placement(frame: group.strongest.frame, alpha: alpha)
                }
            }

            // 新过渡尚未提交时，读仍在显示的旧图标。旧图标消失后不沿用旧位置。
            let pendingRoot = presenters.allSatisfy { $0.portal.layer.presentation() == nil }
            for (kind, track) in outgoingTracks where isActive(kind) && placements[kind] == nil && !ready.contains(kind) {
                guard pendingRoot || waitingForPresentation.contains(kind),
                      track.marker.isDescendant(of: tabBar),
                      let position = placement(for: track, window: window) else { continue }
                placements[kind] = position
            }
        }

        if checkHierarchyMismatchFallback(
            in: tabBar,
            window: window,
            platters: platters,
            placements: placements,
            isTransitioning: !presenters.isEmpty || !candidates.isEmpty,
            hasCoveringModal: hasCoveringModal,
            isSearchTabSelected: isSearchTabSelected,
            selectedPrimaryIsSources: selectedPrimaryIsSources,
            selectedPrimaryIsPackages: selectedPrimaryIsPackages
        ) {
            return
        }

        prepareArtwork(in: window)
        draw(refresh, at: isRefreshing ? placements[.refresh] : nil)
        draw(count, at: countValue != nil ? placements[.count] : nil)
    }

    private func isActive(_ kind: Kind) -> Bool {
        switch kind {
        case .refresh: return isRefreshing
        case .count: return countValue != nil
        }
    }

    private func resetTracks() {
        topology.removeAll(keepingCapacity: true)
        directTracks.removeAll(keepingCapacity: true)
        transitionTracks.removeAll(keepingCapacity: true)
        transitionRootIDs.removeAll(keepingCapacity: true)
        outgoingTracks.removeAll(keepingCapacity: true)
        needsDiscovery = true
    }

    /// 当存在队列弹层、设置页或系统弹窗时，将角标宿主紧贴在根视图分支上方、模态过渡层下方，
    /// 避免红圈浮在模态页面之上；常态置顶于窗口最前，与验收基线一致。
    private func positionHost(in window: UIWindow) -> Bool {
        if let rootBranch = windowRootBranch(in: window),
           let rootIndex = window.subviews.firstIndex(where: { $0 === rootBranch }),
           window.subviews.enumerated().contains(where: { index, subview in
               index > rootIndex && subview !== host && isModalTransitionContainer(subview)
           }) {
            let desiredIndex = rootIndex + 1
            if window.subviews[safe: desiredIndex] !== host {
                window.insertSubview(host, aboveSubview: rootBranch)
            }
            return true
        }
        if window.subviews.last !== host {
            window.bringSubviewToFront(host)
        }
        return false
    }

    private func windowRootBranch(in window: UIWindow) -> UIView? {
        var current = hostView
        while let view = current {
            if view.superview === window {
                return view
            }
            current = view.superview
        }
        return nil
    }

    private func isModalTransitionContainer(_ view: UIView) -> Bool {
        let className = name(view)
        return className == "UITransitionView" || className == "UIDropShadowView"
    }

    /// 稳定可见状态下若长期找不到预期内部视图，自动恢复原 appearance 并回退到系统原生角标。
    private func checkHierarchyMismatchFallback(
        in tabBar: UITabBar,
        window: UIWindow,
        platters: [UIView],
        placements: [Kind: Placement],
        isTransitioning: Bool,
        hasCoveringModal: Bool,
        isSearchTabSelected: Bool,
        selectedPrimaryIsSources: Bool,
        selectedPrimaryIsPackages: Bool
    ) -> Bool {
        guard !isTransitioning,
              !hasCoveringModal,
              !isSearchTabSelected,
              !tabBar.isHidden,
              !tabBar.bounds.isEmpty,
              opacity(of: tabBar, through: window) > 0.01,
              tabBar.convert(tabBar.bounds, to: window).intersects(window.bounds) else {
            mismatchStartTime = nil
            return false
        }

        var expectedKinds: Set<Kind> = []
        if platters.isEmpty {
            if isRefreshing { expectedKinds.insert(.refresh) }
            if countValue != nil { expectedKinds.insert(.count) }
        } else {
            let hasVisibleExpandedPlatter = platters.contains { platter in
                !platter.isHidden &&
                opacity(of: platter, through: tabBar) > 0.01 &&
                platter.bounds.width > platter.bounds.height * 1.5
            }
            if hasVisibleExpandedPlatter {
                if isRefreshing { expectedKinds.insert(.refresh) }
                if countValue != nil { expectedKinds.insert(.count) }
            } else {
                if isRefreshing && selectedPrimaryIsSources { expectedKinds.insert(.refresh) }
                if countValue != nil && selectedPrimaryIsPackages { expectedKinds.insert(.count) }
            }
        }

        guard !expectedKinds.isEmpty else {
            mismatchStartTime = nil
            return false
        }

        let allExpectedResolved = expectedKinds.allSatisfy { placements[$0] != nil }
        if allExpectedResolved {
            mismatchStartTime = nil
            return false
        }

        needsDiscovery = true
        let now = CACurrentMediaTime()
        if let start = mismatchStartTime {
            if now - start >= Self.fallbackGraceDuration {
                activateNativeFallback(in: tabBar)
                return true
            }
        } else {
            mismatchStartTime = now
        }
        return false
    }

    private func activateNativeFallback(in tabBar: UITabBar) {
        isUsingNativeFallback = true
        mismatchStartTime = nil
        resetTracks()
        refresh.isHidden = true
        count.isHidden = true
        refresh.removeAnimation(forKey: "refreshRotation")
        host.removeFromSuperview()
        removeAllMarkers(in: tabBar)
        restoreOriginalAppearances(to: tabBar)
        fallbackRefreshBadge.update(in: tabBar, isRefreshing: isRefreshing)
    }

    private func applyCurrentAppearances(to tabBar: UITabBar) {
        if isUsingNativeFallback {
            restoreOriginalAppearances(to: tabBar)
        } else {
            tabBar.standardAppearance = Self.makingBadgesTransparent(from: originalStandardAppearance)
            tabBar.scrollEdgeAppearance = originalScrollEdgeAppearance.map { Self.makingBadgesTransparent(from: $0) }
        }
    }

    private func restoreOriginalAppearances(to tabBar: UITabBar) {
        tabBar.standardAppearance = originalStandardAppearance.copy()
        tabBar.scrollEdgeAppearance = originalScrollEdgeAppearance?.copy()
    }

    private static func makingBadgesTransparent(from source: UITabBarAppearance) -> UITabBarAppearance {
        let appearance = source.copy()
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected, layout.focused, layout.disabled] {
                state.badgeBackgroundColor = .clear
                var attributes = state.badgeTextAttributes
                attributes[.foregroundColor] = UIColor.clear
                state.badgeTextAttributes = attributes
            }
        }
        return appearance
    }

    private func badgeSize(for kind: Kind) -> CGSize {
        switch kind {
        case .refresh:
            return CGSize(width: Self.diameter, height: Self.diameter)
        case .count:
            guard let text = countValue, !text.isEmpty else {
                return CGSize(width: Self.diameter, height: Self.diameter)
            }
            return countBadgeSize(for: text)
        }
    }

    private func countBadgeSize(for text: String) -> CGSize {
        let title = NSAttributedString(string: text, attributes: Self.countTextAttributes)
        let textWidth = ceil(title.size().width)
        let height = Self.diameter
        // 单数字保持与 Demo v34 一致的 18⅓ pt 正圆，多位数平滑横向扩展为胶囊。
        let width = textWidth <= height - 8 ? height : max(height, textWidth + 10)
        return CGSize(width: width, height: height)
    }

    private func markers(in platter: UIView) -> [Marker] {
        platter.subviews.flatMap(\.subviews)
            .filter { name($0) == "_UITabButton" }
            .compactMap { button in
                button.subviews.compactMap { $0 as? UIImageView }.first(where: { $0.image != nil })
            }
            .compactMap(marker(for:))
    }

    private func marker(for icon: UIImageView) -> Marker? {
        guard let button = icon.superview, name(button) == "_UITabButton",
              let badge = button.subviews.first(where: { name($0) == "_UIBarBadgeView" }),
              !badge.isHidden,
              let label = badge.subviews.compactMap({ $0 as? UILabel }).first?.text,
              !label.isEmpty else {
            removeMarkers(from: icon)
            return nil
        }
        let kind: Kind = label == NativeRefreshBadge.value ? .refresh : .count
        guard isActive(kind) else {
            removeMarkers(from: icon)
            return nil
        }

        // 根据图标尾缘和原生角标的纵向布局确定锚点，不使用屏幕坐标。
        let native = badge.convert(badge.bounds, to: icon)
        guard !native.isEmpty, abs(native.midY - icon.bounds.midY) < icon.bounds.height else { return nil }
        let size = badgeSize(for: kind)
        let inset: CGFloat = 5
        let x = icon.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? icon.bounds.minX + inset - size.width : icon.bounds.maxX - inset
        let frame = CGRect(x: x, y: native.minY, width: size.width, height: size.height)
        if let marker = icon.subviews.compactMap({ $0 as? Marker }).first {
            marker.kind = kind
            if marker.frame != frame { marker.frame = frame }
            return marker
        }
        let marker = Marker(kind: kind, frame: frame)
        icon.addSubview(marker)
        return marker
    }

    private func removeMarkers(from icon: UIView) {
        for subview in icon.subviews where subview is Marker {
            subview.removeFromSuperview()
        }
    }

    private func removeAllMarkers(in root: UIView) {
        for subview in root.subviews {
            if subview is Marker {
                subview.removeFromSuperview()
            } else {
                removeAllMarkers(in: subview)
            }
        }
    }

    private func tracks(in root: UIView) -> [Track]? {
        var hasMorphingPortal = false
        var dedicated: [Track] = []
        var platter: [Track] = []
        let visibilityRoot = root.superview ?? root
        var stack: [(view: UIView, motion: UIView?, viewport: UIView?)] = [(root, nil, nil)]
        while let (view, enclosingMotion, enclosingViewport) = stack.popLast() {
            let startsMotion = name(view) == "_UIMagicMorphView"
            let motion = startsMotion ? view : enclosingMotion
            let viewport = startsMotion || motion == nil ? nil : (enclosingViewport ?? view)
            if let motion, let source = portalSource(view) {
                // 旧版和新版 UIKit 的裁剪视图接口不同，Portal 的实际父子关系都能观察到。
                hasMorphingPortal = true
                if let image = source as? UIImageView, let marker = marker(for: image) {
                    dedicated.append(Track(kind: marker.kind, marker: marker, source: image, portal: view,
                                           motionView: motion, viewport: nil, visibilityRoot: visibilityRoot))
                } else if isPlatter(source), let viewport {
                    platter.append(contentsOf: markers(in: source).map { marker in
                        Track(kind: marker.kind, marker: marker, source: source, portal: view,
                              motionView: nil, viewport: viewport, visibilityRoot: visibilityRoot)
                    })
                }
                continue
            }
            stack.append(contentsOf: view.subviews.map { ($0, motion, viewport) })
        }
        guard hasMorphingPortal else { return nil }
        let dedicatedKinds = Set(dedicated.map(\.kind))
        return dedicated + platter.filter { !dedicatedKinds.contains($0.kind) }
    }

    private func placement(for track: Track, window: UIWindow, view presentedView: UIView? = nil, layer: CALayer? = nil) -> Placement? {
        // 透明锚点由图标持有。读取图标的显示层，锚点本身无需提交独立动画。
        let view = presentedView ?? track.portal ?? track.source
        guard view.window === window,
              let from = layer ?? view.layer.presentation(), let to = host.layer.presentation() else { return nil }
        var alpha = opacity(of: view, through: track.visibilityRoot)
        guard alpha > 0.001 else { return nil }

        let rect: CGRect
        if track.portal != nil {
            let original = track.source.bounds
            guard !original.isEmpty, !from.bounds.isEmpty else { return nil }
            let local = track.marker.convert(track.marker.bounds, to: track.source)
            let sx = from.bounds.width / original.width
            let sy = from.bounds.height / original.height
            rect = CGRect(x: from.bounds.minX + (local.minX - original.minX) * sx,
                          y: from.bounds.minY + (local.minY - original.minY) * sy,
                          width: local.width * sx, height: local.height * sy)
            if let viewport = track.viewport, let clip = viewport.layer.presentation(),
               let icon = track.marker.superview {
                let iconRect = icon.convert(icon.bounds, to: track.source)
                let projectedIcon = CGRect(x: from.bounds.minX + (iconRect.minX - original.minX) * sx,
                                           y: from.bounds.minY + (iconRect.minY - original.minY) * sy,
                                           width: iconRect.width * sx, height: iconRect.height * sy)
                let visible = clip.convert(clip.bounds, to: from).intersection(projectedIcon)
                guard !visible.isEmpty, projectedIcon.width > 0 else { return nil }
                alpha *= min(1, visible.width / projectedIcon.width)
            }
        } else {
            let local = track.marker.frame
            let original = track.source.bounds
            guard !original.isEmpty, !from.bounds.isEmpty else { return nil }
            let sx = from.bounds.width / original.width
            let sy = from.bounds.height / original.height
            rect = CGRect(x: from.bounds.minX + (local.minX - original.minX) * sx,
                          y: from.bounds.minY + (local.minY - original.minY) * sy,
                          width: local.width * sx, height: local.height * sy)
        }

        let frame: CGRect
        if let platter = track.referencePlatter, platter.window === window,
           let platterLayer = platter.layer.presentation() {
            // 保留图标在托盘内的动画，使用托盘实际布局换算到宿主。
            // 标签切换期间，UIKit 可能短暂偏移整条旧的显示树。
            let localFrame = from.convert(rect, to: platterLayer)
            frame = platter.convert(localFrame, to: host)
        } else {
            frame = from.convert(rect, to: to)
        }
        guard !frame.isEmpty, !frame.isInfinite, frame.intersects(host.bounds), alpha.isFinite else { return nil }
        return Placement(frame: frame, alpha: alpha)
    }

    private func opacity(of view: UIView, through root: UIView) -> CGFloat {
        var alpha: CGFloat = 1
        var node: UIView? = view
        while let current = node {
            let layer = current.layer.presentation() ?? current.layer
            if layer.isHidden || current.isHidden { return 0 }
            alpha *= CGFloat(layer.opacity)
            if current === root { break }
            node = current.superview
        }
        return alpha
    }

    private func prepareArtwork(in window: UIWindow) {
        let traits = window.traitCollection
        let scale = max(traits.displayScale, 1)
        let interfaceStyle = traits.userInterfaceStyle
        let contrast = traits.accessibilityContrast

        if let text = countValue, !text.isEmpty {
            let fill = (countBadgeColor ?? .systemRed).resolvedColor(with: traits).cgColor
            let key = CountArtworkKey(text: text, color: fill, scale: scale, interfaceStyle: interfaceStyle, contrast: contrast)
            if countArtworkKey != key {
                countArtworkKey = key
                let size = countBadgeSize(for: text)
                let rect = CGRect(origin: .zero, size: size)
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                format.opaque = false
                let renderer = UIGraphicsImageRenderer(size: size, format: format)
                let title = NSAttributedString(string: text, attributes: Self.countTextAttributes)
                let titleSize = title.size()
                count.contentsScale = scale
                count.contents = renderer.image { context in
                    let graphics = context.cgContext
                    let pill = CGPath(roundedRect: rect,
                                      cornerWidth: rect.height / 2,
                                      cornerHeight: rect.height / 2,
                                      transform: nil)
                    graphics.setFillColor(fill)
                    graphics.addPath(pill)
                    graphics.fillPath()
                    title.draw(at: CGPoint(x: rect.midX - titleSize.width / 2, y: rect.midY - titleSize.height / 2))
                }.cgImage
            }
        } else if countArtworkKey != nil || count.contents != nil {
            countArtworkKey = nil
            count.contents = nil
        }

        if isRefreshing {
            let red = UIColor.systemRed.resolvedColor(with: traits).cgColor
            let key = RefreshArtworkKey(color: red, scale: scale, interfaceStyle: interfaceStyle, contrast: contrast)
            if refreshArtworkKey != key || refreshFrames.isEmpty {
                refreshArtworkKey = key
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                format.opaque = false
                let diameter = Self.diameter
                let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)

                // 红圈和转圈一起栅格化，播放时只提交完整角标帧。
                let spokes = 8
                let frames = (0..<spokes).compactMap { phase in
                    renderer.image { context in
                        let graphics = context.cgContext
                        graphics.setFillColor(red)
                        graphics.fillEllipse(in: rect)
                        graphics.setLineWidth(1.25)
                        graphics.setLineCap(.round)
                        for index in 0..<spokes {
                            let angle = CGFloat(index) * 2 * .pi / CGFloat(spokes)
                            let age = (phase - index + spokes) % spokes
                            graphics.setStrokeColor(UIColor.white.withAlphaComponent(1 - 0.105 * CGFloat(age)).cgColor)
                            graphics.move(to: CGPoint(x: rect.midX + cos(angle) * 2.6, y: rect.midY + sin(angle) * 2.6))
                            graphics.addLine(to: CGPoint(x: rect.midX + cos(angle) * 4.7, y: rect.midY + sin(angle) * 4.7))
                            graphics.strokePath()
                        }
                    }.cgImage
                }
                refreshFrames = frames
                refresh.contentsScale = scale
                refresh.contents = frames.first
                applyRefreshSpinAnimation()
            } else if refresh.animation(forKey: "refreshRotation") == nil {
                applyRefreshSpinAnimation()
            }
        } else if refresh.animation(forKey: "refreshRotation") != nil {
            refresh.removeAnimation(forKey: "refreshRotation")
        }
    }

    private func applyRefreshSpinAnimation() {
        guard !refreshFrames.isEmpty else { return }
        let spin = CAKeyframeAnimation(keyPath: "contents")
        spin.values = refreshFrames
        spin.calculationMode = .discrete
        spin.duration = 0.78
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        refresh.add(spin, forKey: "refreshRotation")
    }

    private func draw(_ badge: CALayer, at placement: Placement?) {
        guard let placement, placement.alpha > 0.001 else {
            if !badge.isHidden { badge.isHidden = true }
            return
        }
        let position = CGPoint(x: placement.frame.midX, y: placement.frame.midY)
        let bounds = CGRect(origin: .zero, size: placement.frame.size)
        if badge.position != position { badge.position = position }
        if badge.bounds != bounds { badge.bounds = bounds }
        if badge.opacity != Float(placement.alpha) { badge.opacity = Float(placement.alpha) }
        if badge.isHidden { badge.isHidden = false }
    }

    private func portalSource(_ view: UIView) -> UIView? {
        guard name(view) == Self.portalClass, view.responds(to: Self.sourceSelector) else { return nil }
        return view.perform(Self.sourceSelector)?.takeUnretainedValue() as? UIView
    }

    private func name(_ view: UIView) -> String { NSStringFromClass(type(of: view)) }
    private func isPlatter(_ view: UIView) -> Bool { name(view).contains("PlatterView") }
}
