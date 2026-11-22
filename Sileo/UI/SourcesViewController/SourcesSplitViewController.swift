//
//  SourcesSplitViewController.swift
//  Sileo
//
//  Created by CoolStar on 1/2/21.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

@available(iOS 26.0, *)
final class SourcesSplitScrollCoordinator {
    weak var splitViewController: SourcesSplitViewController?
    private var needsRebind = true
    private weak var lastBoundScrollView: UIScrollView?

    func isActive(_ scrollView: UIScrollView) -> Bool {
        lastBoundScrollView === scrollView
    }

    func markNeedsRebind(from sourceScrollView: UIScrollView? = nil) {
        // 若是当前已绑定列在用户拖拽中途因大标题缩放触发 inset 变化，绝不在拖拽中途重绑重置灵敏度。
        if let src = sourceScrollView, src === lastBoundScrollView, src.isDragging {
            return
        }
        needsRebind = true
    }

    func activate(_ scrollView: UIScrollView, forceRebind: Bool = false) {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              let split = splitViewController,
              split.style != .unspecified else {
            return
        }

        let currentBottom = split.contentScrollView(for: .bottom)
        let switchingColumn = (currentBottom !== scrollView || lastBoundScrollView !== scrollView)
        // 拖拽中途绝不对同一列执行 nil->sv 重置，避免抹掉 _UIScrollAwayInteraction 的滚动累计量。
        let shouldRebind = switchingColumn || forceRebind || (needsRebind && !scrollView.isDragging)
        guard shouldRebind else { return }

        needsRebind = false
        lastBoundScrollView = scrollView

        // 若另一列仍在惯性滑动或处于越界回弹，先同步停住并刷新其布局，
        // 防止另一列后续几帧回弹经由 UINavigationController 把底栏的滚动观测抢走。
        for column in [UISplitViewController.Column.primary, .supplementary, .secondary] {
            guard let otherColVC = split.viewController(for: column),
                  let otherSV = split.columnScrollView(for: column),
                  otherSV !== scrollView else {
                continue
            }
            let cur = otherSV.contentOffset
            let minY = -otherSV.adjustedContentInset.top
            let maxY = max(minY, otherSV.contentSize.height - otherSV.bounds.height + otherSV.adjustedContentInset.bottom)
            let clampedY = min(max(cur.y, minY), maxY)
            if otherSV.refreshControl?.isRefreshing == true && cur.y < minY {
                continue
            }
            if otherSV.isDecelerating || abs(cur.y - clampedY) > 0.5 {
                otherSV.setContentOffset(CGPoint(x: cur.x, y: clampedY), animated: false)
                otherColVC.view.layoutIfNeeded()
            }
        }

        if currentBottom === scrollView {
            split.setContentScrollView(nil, for: .bottom)
        }
        split.setContentScrollView(scrollView, for: .bottom)
    }
}

@available(iOS 26.0, *)
private final class SourcesSplitColumnScrollTracker: NSObject, UIGestureRecognizerDelegate {
    weak var splitViewController: SourcesSplitViewController?
    let column: UISplitViewController.Column
    private weak var attachedView: UIView?
    private var recognizer: UIPanGestureRecognizer?

    init(splitViewController: SourcesSplitViewController, column: UISplitViewController.Column) {
        self.splitViewController = splitViewController
        self.column = column
        super.init()
    }

    func attach(to view: UIView) {
        if attachedView === view, recognizer?.view === view {
            return
        }
        if let existing = recognizer, let oldView = existing.view {
            oldView.removeGestureRecognizer(existing)
        }
        // 使用 UIPanGestureRecognizer + allowedScrollTypesMask = .all，
        // 同时兼容手指触摸与触控板/鼠标滚轮事件，且 shouldReceive 返回 false 绝不拦截业务手势。
        let gr = UIPanGestureRecognizer()
        gr.allowedScrollTypesMask = .all
        gr.cancelsTouchesInView = false
        gr.delaysTouchesBegan = false
        gr.delaysTouchesEnded = false
        gr.delegate = self
        view.addGestureRecognizer(gr)
        attachedView = view
        recognizer = gr
    }

    private func activateColumnScrollView() {
        guard let split = splitViewController,
              TabBarController.singleton?.popupIsPresented == true,
              let sv = split.columnScrollView(for: column),
              !sv.isDragging else {
            return
        }
        split.padScrollCoordinator?.activate(sv, forceRebind: false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        activateColumnScrollView()
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        if event.type == .scroll {
            activateColumnScrollView()
        }
        return false
    }
}

class SourcesSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate {
    private var displayModeBeforePackageDetail: UISplitViewController.DisplayMode?
    private var isTrackingPackageDetailVisibility = false
    private var pendingAutomaticDisplayMode: UISplitViewController.DisplayMode?
    private var isAdaptingToWindowSize = false
    private var padScrollCoordinatorStorage: AnyObject?
    private var columnTrackersStorage: [Int: AnyObject] = [:]

    @available(iOS 26.0, *)
    var padScrollCoordinator: SourcesSplitScrollCoordinator? {
        guard UIDevice.current.userInterfaceIdiom == .pad, style != .unspecified else {
            return nil
        }
        if let existing = padScrollCoordinatorStorage as? SourcesSplitScrollCoordinator {
            return existing
        }
        let coordinator = SourcesSplitScrollCoordinator()
        coordinator.splitViewController = self
        padScrollCoordinatorStorage = coordinator
        return coordinator
    }

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
            attachColumnScrollTrackersIfNeeded()
        } else {
            preferredDisplayMode = .allVisible
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if #available(iOS 26.0, *) {
            configurePackageDetailNavigation()
            updatePrimaryVisibilityForCurrentDetail(animated: false)
            attachColumnScrollTrackersIfNeeded()
            padScrollCoordinator?.markNeedsRebind()
        }
    }

    @available(iOS 26.0, *)
    func columnScrollView(for column: UISplitViewController.Column) -> UIScrollView? {
        guard let colVC = viewController(for: column) else {
            return nil
        }
        let topVC = (colVC as? UINavigationController)?.topViewController ?? colVC
        if let sourcesVC = topVC as? SourcesViewController, let tableView = sourcesVC.tableView {
            return tableView
        }
        if let tableVC = topVC as? UITableViewController {
            return tableVC.tableView
        }
        if let packageListVC = topVC as? PackageListViewController, let collectionView = packageListVC.collectionView {
            return collectionView
        }
        return topVC.contentScrollView(for: .top) ?? colVC.contentScrollView(for: .top)
    }

    @available(iOS 26.0, *)
    func activateColumnScrollView(containing hitView: UIView) {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              style != .unspecified,
              let coordinator = padScrollCoordinator else {
            return
        }
        for column in [UISplitViewController.Column.primary, .supplementary, .secondary] {
            guard let colVC = viewController(for: column),
                  colVC.isViewLoaded,
                  hitView.isDescendant(of: colVC.view) else {
                continue
            }
            if let sv = columnScrollView(for: column), !sv.isDragging {
                coordinator.activate(sv, forceRebind: false)
            }
            return
        }
    }

    @available(iOS 26.0, *)
    func containsColumnScrollView(_ scrollView: UIScrollView) -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad, style != .unspecified else {
            return false
        }
        for column in [UISplitViewController.Column.primary, .supplementary, .secondary] {
            if columnScrollView(for: column) === scrollView {
                return true
            }
        }
        return false
    }

    @available(iOS 26.0, *)
    private func attachColumnScrollTrackersIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad, style != .unspecified else {
            return
        }
        for column in [UISplitViewController.Column.primary, .supplementary, .secondary] {
            guard let colVC = viewController(for: column), colVC.isViewLoaded else {
                continue
            }
            let tracker: SourcesSplitColumnScrollTracker
            if let existing = columnTrackersStorage[column.rawValue] as? SourcesSplitColumnScrollTracker {
                tracker = existing
            } else {
                let created = SourcesSplitColumnScrollTracker(splitViewController: self, column: column)
                columnTrackersStorage[column.rawValue] = created
                tracker = created
            }
            tracker.attach(to: colVC.view)
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
            self?.attachColumnScrollTrackersIfNeeded()
            self?.padScrollCoordinator?.markNeedsRebind()
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
            attachColumnScrollTrackersIfNeeded()
            padScrollCoordinator?.markNeedsRebind()
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
            attachColumnScrollTrackersIfNeeded()
            padScrollCoordinator?.markNeedsRebind()
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
        attachColumnScrollTrackersIfNeeded()
        padScrollCoordinator?.markNeedsRebind()
    }
}
