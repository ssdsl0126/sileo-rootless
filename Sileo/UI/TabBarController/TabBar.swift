//
//  TabBar.swift
//  Sileo
//
//  Created by CoolStar on 7/27/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

class TabBar: UITabBar {
    private weak var decorationHost: UIView?
    private let decorationView: UIView = {
        let view = UIView()
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.accessibilityElementsHidden = true
        view.accessibilityIdentifier = "Sileo.TabDecorations"
        return view
    }()
    private let compactImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.accessibilityIdentifier = "Sileo.CompactTabImage"
        view.isHidden = true
        return view
    }()
    private let refreshBadge = TabRefreshBadgeView()
    private let compactBadgeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()
    private weak var compactItem: UITabBarItem?
    private var compactImage: UIImage?
    private var renderedCompactImage: UIImage?
    private var renderedCompactColor: UIColor?
    private var compactItemIndex = 0
    private var searchTabIsActive = false
    private var compactImageIsSettled = false
    private var sourceRefreshIsVisible = false
    private var lastCompactFrame: CGRect?
    private var lastCompactTime: CFTimeInterval = 0
    private var lastSourceFrame: CGRect?
    private var lastSourceTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var trackingDeadline: CFTimeInterval = 0
    private lazy var displayLinkTarget = TabDecorationDisplayLinkTarget(tabBar: self)

    private var supportsDecorations: Bool {
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone { return true }
        return false
    }

    deinit {
        displayLink?.invalidate()
        decorationView.removeFromSuperview()
    }

    // 装饰与 UITabBar 是控制器根视图中的独立分支，不参与玻璃内容的遮罩、着色和淡出。
    func attachDecorations(to host: UIView) {
        guard supportsDecorations else { return }
        decorationHost = host
        if decorationView.superview !== host {
            decorationView.addSubview(compactImageView)
            decorationView.addSubview(compactBadgeLabel)
            decorationView.addSubview(refreshBadge)
            host.addSubview(decorationView)
        }
        updateDecorations()
    }

    func prepareForTabSelection(index: Int, item: UITabBarItem?,
                                previousIndex: Int, previousItem: UITabBarItem?) {
        guard supportsDecorations else { return }
        let isSearch = index == 4
        if !isSearch || !searchTabIsActive {
            compactItemIndex = isSearch ? previousIndex : index
            let sourceItem = isSearch ? previousItem : item
            compactItem = sourceItem
            // 系统标签的 item.image 可能为空，切换前从当前按钮读取一次并保留。
            compactImage = sourceItem?.image ?? sourceItem?.selectedImage
                ?? tabImage(in: self, title: tabTitle(at: compactItemIndex))?.image
            lastCompactFrame = nil
            compactImageIsSettled = false
            compactImageView.isHidden = true
        }
        searchTabIsActive = isSearch
        updateDecorations()
        trackDecorationTransition()
    }

    func setSourceRefreshIndicatorVisible(_ visible: Bool) {
        guard supportsDecorations, sourceRefreshIsVisible != visible else { return }
        sourceRefreshIsVisible = visible
        refreshBadge.setRefreshing(visible)
        if !visible {
            lastSourceFrame = nil
            refreshBadge.isHidden = true
        }
        updateDecorations()
        trackDecorationTransition()
    }

    func trackSourceRefreshScrollTransition() {
        guard supportsDecorations, sourceRefreshIsVisible, !searchTabIsActive else { return }
        // 滚动驱动的合成动画不一定触发标签栏布局，不能依赖上一次布局留下的跟踪窗口。
        updateDecorations()
        trackDecorationTransition()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard supportsDecorations else { return }
        updateDecorations()
        trackDecorationTransition()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDecorationTracking()
            decorationView.isHidden = true
        } else if supportsDecorations {
            updateDecorations()
            trackDecorationTransition()
        }
    }

    private func trackDecorationTransition() {
        guard supportsDecorations, window != nil,
              searchTabIsActive || sourceRefreshIsVisible else { return }
        // layoutSubviews 不会随合成动画逐帧调用；仅在布局或切换后的短时间内跟踪显示位置。
        trackingDeadline = CACurrentMediaTime() + 1
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(TabDecorationDisplayLinkTarget.tick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func updateDecorationAnimation() {
        updateDecorations()
        if CACurrentMediaTime() >= trackingDeadline {
            stopDecorationTracking()
        }
    }

    private func stopDecorationTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func updateDecorations() {
        guard supportsDecorations, let host = decorationHost,
              window != nil, window === host.window else {
            decorationView.isHidden = true
            return
        }
        let opacity = visibleOpacity(of: self, upTo: host)
        decorationView.isHidden = opacity <= 0.01
        guard opacity > 0.01 else { return }
        if decorationView.frame != host.bounds {
            decorationView.frame = host.bounds
            decorationView.bounds = host.bounds
        }
        if host.subviews.last !== decorationView {
            host.bringSubviewToFront(decorationView)
        }
        // 只操作自有视图，不重排系统子视图，也不向系统按钮添加约束。
        UIView.performWithoutAnimation {
            decorationView.alpha = opacity
            updateDecorationFrames(in: host)
        }
    }

    private func updateDecorationFrames(in host: UIView) {
        let now = CACurrentMediaTime()
        let barFrame = displayedFrame(of: self, in: host)
        let allPlatters = tabPlatters(in: self)
        let platters = allPlatters.filter { visibleOpacity(of: $0, upTo: self) > 0.01 }
        let morphLayers = window.map { tabMorphLayers(in: $0) } ?? []
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let compactPlatter = platters.first {
            let frame = displayedFrame(of: $0, in: host)
            return validFrame(frame) && frame.width <= frame.height * 1.5 &&
                (isRightToLeft ? frame.midX > barFrame.midX : frame.midX < barFrame.midX)
        }
        let hasFullPlatter = platters.contains {
            let frame = displayedFrame(of: $0, in: host)
            return validFrame(frame) && frame.width > frame.height * 1.5
        }

        var compactFrame: CGRect?
        if let platter = compactPlatter {
            let platterFrame = displayedFrame(of: platter, in: host)
            let source = tabImage(in: platter, title: tabTitle(at: compactItemIndex))
            let sourceFrame = source.map { displayedFrame(of: $0, in: host) }
            if let sourceFrame, validFrame(sourceFrame),
               sourceFrame.width <= platterFrame.width, sourceFrame.height <= platterFrame.height,
               platterFrame.contains(CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)) {
                compactFrame = sourceFrame
            } else {
                // 内容重挂载时仍有玻璃按钮的显示位置，缓存图标可在这里连续绘制。
                compactFrame = CGRect(x: platterFrame.midX - 13, y: platterFrame.midY - 13, width: 26, height: 26)
            }
            if compactImage == nil { compactImage = source?.image }
            lastCompactFrame = compactFrame
            lastCompactTime = now
        } else if !hasFullPlatter, now - lastCompactTime < 0.15 {
            compactFrame = lastCompactFrame
        }

        // 原图标已在终点，屏幕上移动的是窗口中的 morph 副本；补绘与角标必须跟随同一份副本。
        var compactImageIsMoving = false
        if let frame = compactFrame, let morph = matchingMorph(in: morphLayers, frame: frame, host: host) {
            compactFrame = displayedMorphFrame(morph, in: host)
            if let displayed = compactFrame {
                // 移动时保留系统图标，避免采样与合成相差一帧造成重影；到位后再补足交接期间的空帧。
                let isAtDestination = abs(displayed.midX - frame.midX) <= 1 && abs(displayed.midY - frame.midY) <= 1
                compactImageIsSettled = compactImageIsSettled || isAtDestination
                // AnimationKit 会把两端原图标一起淡出，这种合成路径需要沿移动位置持续补绘。
                let usesLayerMorph = NSStringFromClass(type(of: morph)) == "AnimationKit.MagicMorphLayer"
                compactImageIsMoving = !compactImageIsSettled && !usesLayerMorph
            }
        }
        let showsCompactImage = searchTabIsActive && compactFrame != nil && compactImage != nil && !compactImageIsMoving
        compactImageView.isHidden = !showsCompactImage
        var showsCompactBadge = false
        if showsCompactImage, let frame = compactFrame, let image = compactImage {
            let color = (unselectedItemTintColor ?? .label).resolvedColor(with: traitCollection)
            if renderedCompactImage !== image || renderedCompactColor != color {
                renderedCompactImage = image
                renderedCompactColor = color
                compactImageView.image = image.withTintColor(color, renderingMode: .alwaysOriginal)
            }
            compactImageView.frame = frame
            // 其它标签的更新数量也必须在补绘图标前面，避免把遮挡问题转移到软件包标签。
            if compactItemIndex != 2, let value = compactItem?.badgeValue, !value.isEmpty {
                compactBadgeLabel.text = value
                compactBadgeLabel.backgroundColor = compactItem?.badgeColor ?? .systemRed
                let width = max(20, ceil(compactBadgeLabel.intrinsicContentSize.width) + 10)
                compactBadgeLabel.frame = CGRect(x: frame.maxX - 10, y: frame.minY - 8, width: width, height: 20)
                showsCompactBadge = true
            }
        }
        compactBadgeLabel.isHidden = !showsCompactBadge

        guard sourceRefreshIsVisible else {
            refreshBadge.isHidden = true
            return
        }
        var sourceFrame: CGRect?
        if !searchTabIsActive {
            sourceFrame = sourceRefreshFrame(in: host, platters: allPlatters, morphLayers: morphLayers)
        } else if let compactFrame {
            if compactItemIndex == 2 { sourceFrame = compactFrame }
        } else {
            let title = tabTitle(at: 2)
            // 只用完整标签栏的普通图标定位，选中透镜的放大副本不作为锚点。
            for platter in allPlatters where !platter.isHidden {
                let frame = displayedFrame(of: platter, in: host)
                guard frame.width > frame.height * 1.5,
                      let source = tabImage(in: platter, title: title) else { continue }
                let candidate = displayedFrame(of: source, in: host)
                if validFrame(candidate), frame.intersects(candidate) {
                    if let morph = matchingMorph(in: morphLayers, frame: candidate, host: host) {
                        sourceFrame = displayedMorphFrame(morph, in: host)
                            ?? (compactItemIndex == 2 ? lastSourceFrame : nil)
                    } else if visibleOpacity(of: platter, upTo: self) > 0.01 {
                        sourceFrame = candidate
                    }
                    break
                }
            }
        }
        if let sourceFrame {
            lastSourceFrame = sourceFrame
            lastSourceTime = now
        } else if searchTabIsActive, compactFrame == nil, !hasFullPlatter, now - lastSourceTime < 0.15 {
            sourceFrame = lastSourceFrame
        }
        guard let sourceFrame else {
            refreshBadge.isHidden = true
            return
        }
        refreshBadge.frame = CGRect(x: sourceFrame.maxX - 10, y: sourceFrame.minY - 8, width: 20, height: 20)
        refreshBadge.isHidden = false
        // 角标始终是自有前景层中图标之后的子视图，整个红圈和白色转圈一起置前。
        refreshBadge.setRefreshing(true)
    }

    private func sourceRefreshFrame(in host: UIView, platters: [UIView], morphLayers: [CALayer]) -> CGRect? {
        // 与队列滚动逻辑读取同一个原生目标；accessory 的 inline 通知不能代表动画起点。
        var isMinimized = false
        if let ivar = class_getInstanceVariable(UITabBar.self, "_visualProvider"),
           let provider = object_getIvar(self, ivar) as? NSObject,
           NSStringFromClass(type(of: provider)).contains("_UITabBarVisualProvider_Floating") {
            isMinimized = (provider.value(forKey: "_currentMorphTarget") as? NSNumber)?.intValue == 2
        }
        // 其它页面收缩时软件源图标会退场，不能把它的旧角标留在队列上方。
        guard !isMinimized || compactItemIndex == 2 else { return nil }

        let barFrame = convert(bounds, to: host)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for platter in platters where !platter.isHidden {
            // 用布局终点选择完整或紧凑容器；显示层宽度在动画中仍可能接近完整菜单。
            let targetPlatterFrame = platter.convert(platter.bounds, to: host)
            guard validFrame(targetPlatterFrame) else { continue }
            let isCompact = targetPlatterFrame.width <= targetPlatterFrame.height * 1.5
            guard isCompact == isMinimized else { continue }
            if isCompact,
               isRightToLeft ? targetPlatterFrame.midX <= barFrame.midX : targetPlatterFrame.midX >= barFrame.midX {
                continue
            }
            let source = tabImage(in: platter, title: tabTitle(at: 2))
            let target: CGRect
            if let source {
                target = source.convert(source.bounds, to: host)
            } else if isCompact {
                // 紧凑按钮重挂载期间可能没有标题或原图标，使用与现有紧凑图标相同的中心位置。
                target = CGRect(x: targetPlatterFrame.midX - 13, y: targetPlatterFrame.midY - 13, width: 26, height: 26)
            } else {
                continue
            }
            guard validFrame(target), targetPlatterFrame.contains(CGPoint(x: target.midX, y: target.midY)) else { continue }

            // morph 按目标矩形匹配，再取移动中的显示矩形，不能拿旧图标的显示矩形匹配终点。
            if let morph = matchingMorph(in: morphLayers, frame: target, host: host),
               let displayed = displayedMorphFrame(morph, in: host), validFrame(displayed) {
                return displayed
            }
            if visibleOpacity(of: platter, upTo: self) > 0.01 {
                let platterFrame = displayedFrame(of: platter, in: host)
                let displayed = source.map { displayedFrame(of: $0, in: host) }
                    ?? CGRect(x: platterFrame.midX - 13, y: platterFrame.midY - 13, width: 26, height: 26)
                if validFrame(displayed) { return displayed }
            }
        }
        // 交接时找不到有效图标就暂时隐藏，不回用完整菜单的旧位置。
        return nil
    }

    private func tabTitle(at index: Int) -> String {
        let keys = ["Featured_Page", "News_Page", "Sources_Page", "Packages_Page", "Search_Page"]
        guard keys.indices.contains(index) else { return "" }
        return String(localizationKey: keys[index])
    }

    private func tabPlatters(in view: UIView) -> [UIView] {
        if NSStringFromClass(type(of: view)).contains("TabBarPlatterView") { return [view] }
        return view.subviews.flatMap { tabPlatters(in: $0) }
    }

    private func tabImage(in view: UIView, title: String) -> UIImageView? {
        let className = NSStringFromClass(type(of: view))
        guard !className.contains("SelectedContentView"), !className.contains("Badge") else { return nil }
        if view is UIControl, containsTitle(title, in: view), let image = firstImage(in: view) {
            return image
        }
        return view.subviews.lazy.compactMap { self.tabImage(in: $0, title: title) }.first
    }

    private func firstImage(in view: UIView) -> UIImageView? {
        let className = NSStringFromClass(type(of: view))
        guard !className.contains("Badge"), !className.contains("SelectedContentView") else { return nil }
        if let image = view as? UIImageView, image.image != nil { return image }
        // 外层 UIControl 可能包含整组标签，不能把另一个按钮的图片误认成本按钮图片。
        return view.subviews.lazy.filter { !($0 is UIControl) }.compactMap { self.firstImage(in: $0) }.first
    }

    private func containsTitle(_ title: String, in view: UIView) -> Bool {
        if let label = view as? UILabel, label.text == title { return true }
        return view.subviews.contains { containsTitle(title, in: $0) }
    }

    private func displayedFrame(of view: UIView, in host: UIView) -> CGRect {
        // UIKit 重挂载时 presentation() 可能仍存在，但已经脱离窗口；跨树换算会丢掉标签栏偏移。
        if let layer = connectedPresentationLayer(of: view),
           let hostLayer = connectedPresentationLayer(of: host) {
            return layer.convert(layer.bounds, to: hostLayer)
        }
        return view.convert(view.bounds, to: host)
    }

    private func visibleOpacity(of view: UIView, upTo host: UIView) -> CGFloat {
        var opacity: CGFloat = 1
        var current: UIView? = view
        while let currentView = current, currentView !== host {
            let layer = connectedPresentationLayer(of: currentView) ?? currentView.layer
            if layer.isHidden { return 0 }
            opacity *= CGFloat(layer.opacity)
            current = currentView.superview
        }
        return opacity
    }

    private func connectedPresentationLayer(of view: UIView) -> CALayer? {
        guard let layer = view.layer.presentation(), let windowLayer = view.window?.layer else { return nil }
        var ancestor: CALayer? = layer
        while let current = ancestor {
            if current.model() === windowLayer { return layer }
            ancestor = current.superlayer
        }
        return nil
    }

    private func tabMorphLayers(in view: UIView) -> [CALayer] {
        var result: [CALayer] = []
        let name = NSStringFromClass(type(of: view))
        if (name == "_UIMagicMorphView" || name == "UIKit.MagicMorphView"), !view.isHidden {
            // 新运行时把内部图标从 UIView 移到了 AnimationKit 图层，统一读取实际参与 morph 的层。
            result.append(view.layer)
            appendMorphLayers(in: view.layer, to: &result)
        }
        for child in view.subviews { result += tabMorphLayers(in: child) }
        return result
    }

    private func appendMorphLayers(in layer: CALayer, to result: inout [CALayer]) {
        for child in layer.sublayers ?? [] {
            if NSStringFromClass(type(of: child)) == "AnimationKit.MagicMorphLayer" { result.append(child) }
            appendMorphLayers(in: child, to: &result)
        }
    }

    private func matchingMorph(in layers: [CALayer], frame: CGRect, host: UIView) -> CALayer? {
        // 用目标图标的完整矩形匹配，避免把搜索图标或整块玻璃容器当成软件源图标。
        layers.first {
            let target = $0.convert($0.bounds, to: host.layer)
            return abs(target.minX - frame.minX) < 1 && abs(target.minY - frame.minY) < 1 &&
                abs(target.width - frame.width) < 1 && abs(target.height - frame.height) < 1
        }
    }

    private func displayedMorphFrame(_ layer: CALayer, in host: UIView) -> CGRect? {
        guard let presentation = layer.presentation(), let windowLayer = window?.layer,
              let hostLayer = connectedPresentationLayer(of: host) else { return nil }
        var ancestor: CALayer? = presentation
        while let current = ancestor {
            if current.model() === windowLayer { return presentation.convert(presentation.bounds, to: hostLayer) }
            ancestor = current.superlayer
        }
        return nil
    }

    private func validFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
    }

    override var traitCollection: UITraitCollection {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return super.traitCollection
        }
        if UIApplication.shared.statusBarOrientation.isLandscape && self.bounds.width >= 400 {
            return super.traitCollection
        }
        return UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(horizontalSizeClass: .compact)])
    }
}

private final class TabDecorationDisplayLinkTarget: NSObject {
    weak var tabBar: TabBar?

    init(tabBar: TabBar) {
        self.tabBar = tabBar
    }

    @objc func tick(_ sender: CADisplayLink) {
        tabBar?.updateDecorationAnimation()
    }
}

private final class TabRefreshBadgeView: UIView {
    private let indicator = UIActivityIndicatorView(style: .medium)

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        backgroundColor = .systemRed
        layer.cornerRadius = 10
        isUserInteractionEnabled = false
        isHidden = true
        accessibilityIdentifier = "Sileo.SourceRefreshBadge"
        indicator.color = .white
        indicator.transform = CGAffineTransform(scaleX: 0.56, y: 0.56)
        indicator.accessibilityIdentifier = "Sileo.SourceRefreshIndicator"
        addSubview(indicator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        indicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func setRefreshing(_ refreshing: Bool) {
        if refreshing && !indicator.isAnimating { indicator.startAnimating() }
        if !refreshing && indicator.isAnimating { indicator.stopAnimating() }
    }
}
