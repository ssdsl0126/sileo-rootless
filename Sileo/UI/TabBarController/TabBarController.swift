//
//  TabBarController.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import LNPopupController

class TabBarController: UITabBarController, UITabBarControllerDelegate {
    static var singleton: TabBarController?
    private var downloadsController: UINavigationController?
    private(set) public var popupIsPresented = false
    private var popupLock = DispatchSemaphore(value: 1)
    private var shouldSelectIndex = -1
    private var fuckedUpSources = false
    private var popupTapGesture: UITapGestureRecognizer?
    private var queueCardController: QueueFloatingCardController?
    private var isPresentingQueueCard = false
    
    private var preferredPopupInteractionStyle: UIViewController.PopupInteractionStyle {
        UIDevice.current.userInterfaceIdiom == .phone ? .snap : .drag
    }

    private var usesFloatingQueueCardOnPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var queueCollapsedInteractionStyle: UIViewController.PopupInteractionStyle {
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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
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
        if usesFloatingQueueCardOnPhone, (queueCardController != nil || isPresentingQueueCard) {
            completion?()
            return
        }

        guard let downloadsController = downloadsController,
              !popupIsPresented
        else {
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
        self.popupBar.progressViewStyle = .bottom
        self.popupInteractionStyle = queueCollapsedInteractionStyle
        self.presentPopupBar(with: downloadsController, animated: true, completion: completion)
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
        self.dismissPopupBar(animated: true, completion: completion)
    }
    
    func presentPopupController() {
        self.presentPopupController(completion: nil)
    }
    
    func presentPopupController(completion: (() -> Void)?) {
        if usesFloatingQueueCardOnPhone {
            presentFloatingQueueCard(completion: completion)
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
        if usesFloatingQueueCardOnPhone, let queueCardController = queueCardController {
            queueCardController.dismissCard(completion: completion)
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
        if queueCardController != nil || isPresentingQueueCard {
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

    private func configurePopupTapIfNeeded() {
        guard usesFloatingQueueCardOnPhone else {
            return
        }
        if popupTapGesture == nil {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handlePopupBarTap))
            popupTapGesture = gesture
            popupBar.addGestureRecognizer(gesture)
        }
    }

    @objc private func handlePopupBarTap() {
        guard usesFloatingQueueCardOnPhone,
              popupIsPresented,
              queueCardController == nil
        else {
            return
        }
        presentPopupController()
    }

    private func presentFloatingQueueCard(completion: (() -> Void)?) {
        guard usesFloatingQueueCardOnPhone,
              popupIsPresented,
              !isPresentingQueueCard,
              queueCardController == nil,
              let downloadsController = downloadsController
        else {
            completion?()
            return
        }

        isPresentingQueueCard = true
        popupIsPresented = false
        dismissPopupBar(animated: false) { [weak self] in
            guard let self = self else { return }
            let queueCard = QueueFloatingCardController(contentController: downloadsController)
            queueCard.onDismiss = { [weak self] in
                self?.queueCardController = nil
                self?.isPresentingQueueCard = false
                self?.updatePopup()
            }
            self.queueCardController = queueCard
            self.present(queueCard, animated: false) {
                completion?()
            }
        }
    }
    
    @objc func updateSileoColors() {
        self.popupBar.tintColor = UINavigationBar.appearance().tintColor
        self.setNeedsPopupBarAppearanceUpdate()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.tabBar.itemPositioning = .centered
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.updatePopup()
        }
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

private final class QueueFloatingCardController: UIViewController, UIGestureRecognizerDelegate {
    private let contentController: UIViewController
    private let dimmingView = UIControl(frame: .zero)
    private let cardContainerView = UIView(frame: .zero)
    private let grabberView = UIView(frame: .zero)
    private var panGesture: UIPanGestureRecognizer?
    private var didAnimateIn = false
    private var isDismissing = false
    private let baseDimmingAlpha: CGFloat = 0.72
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

        switch gesture.state {
        case .changed:
            cardContainerView.transform = CGAffineTransform(translationX: 0, y: offsetY)
            dimmingView.alpha = baseDimmingAlpha * (1 - (progress * 0.85))
        case .ended, .cancelled:
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
        return true
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
