//
//  PackageCollectionViewCell.swift
//  Sileo
//
//  Created by CoolStar on 7/30/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit
import SwipeCellKit
import Evander

@available(iOS 26.0, *)
private struct PackageSwipeActionTransition: SwipeActionTransitioning {
    let backgroundColor: UIColor

    func didTransition(with context: SwipeActionTransitioningContext) {
        let button = context.button
        context.setBackgroundColor(.clear)

        if button.layer.name != "Sileo.PackageSwipeAction" {
            button.frame = button.frame.insetBy(dx: 4, dy: 4)
            button.layer.name = "Sileo.PackageSwipeAction"
        }

        button.backgroundColor = backgroundColor
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = min(14, button.bounds.height / 2)
        button.layer.masksToBounds = true
    }
}

class PackageCollectionViewCell: SwipeCollectionViewCell {
    @IBOutlet var imageView: UIImageView?
    @IBOutlet var titleLabel: UILabel?
    @IBOutlet var authorLabel: UILabel?
    @IBOutlet var descriptionLabel: UILabel?
    @IBOutlet var separatorView: UIView?
    @IBOutlet var unreadView: UIView?
    
    var item: CGFloat = 0
    var numberOfItems: CGFloat = 0
    var alwaysHidesSeparator = false
    var stateBadgeView: PackageStateBadgeView?
    private let localDebProgressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.progress = 0
        view.clipsToBounds = true
        view.layer.cornerRadius = 1.5
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if #available(iOS 26.0, *),
           traitCollection.userInterfaceIdiom == .pad,
           event?.type != .touches {
            // SwipeCellKit 会在命中测试离开已展开的 cell 时自动收起；
            // iPad 鼠标悬停会持续触发非触摸命中测试，因此不能沿用该副作用。
            return bounds.contains(point)
        }
        return super.point(inside: point, with: event)
    }
    
    public var targetPackage: Package? {
        didSet {
            if let targetPackage = targetPackage {
                titleLabel?.text = targetPackage.name
                authorLabel?.text = "\(targetPackage.author?.name ?? "Unknown") • \(targetPackage.version)"
                descriptionLabel?.text = targetPackage.packageDescription
                
                let url = targetPackage.icon
                EvanderNetworking.image(url: url, condition: { [weak self] in self?.targetPackage?.icon == url }, imageView: imageView, fallback: targetPackage.defaultIcon)
                        
                titleLabel?.textColor = targetPackage.commercial ? self.tintColor : .sileoLabel
            }
            unreadView?.isHidden = true
            
            self.accessibilityLabel = String(format: String(localizationKey: "Package_By_Author"),
                                             self.titleLabel?.text ?? "", self.authorLabel?.text ?? "")
            
            self.refreshState()
        }
    }
    
    public var provisionalTarget: ProvisionalPackage? {
        didSet {
            if let provisionalTarget = provisionalTarget {
                titleLabel?.text = provisionalTarget.name ?? ""
                authorLabel?.text = "\(provisionalTarget.author?.name ?? "") • \(provisionalTarget.version)"
                descriptionLabel?.text = provisionalTarget.description
            
                let url = provisionalTarget.icon
                EvanderNetworking.image(url: url, condition: { [weak self] in self?.provisionalTarget?.icon == url }, imageView: imageView, fallback: provisionalTarget.defaultIcon)

                titleLabel?.textColor = .sileoLabel
            }
            unreadView?.isHidden = true
            
            self.accessibilityLabel = String(format: String(localizationKey: "Package_By_Author"),
                                             self.titleLabel?.text ?? "", self.authorLabel?.text ?? "")
            
            self.refreshState()
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.selectedBackgroundView = UIView()
        self.selectedBackgroundView?.backgroundColor = UIColor.lightGray.withAlphaComponent(0.25)
        
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
        self.delegate = self
        
        stateBadgeView = PackageStateBadgeView(frame: .zero)
        stateBadgeView?.translatesAutoresizingMaskIntoConstraints = false
        stateBadgeView?.state = .installed
        
        if let stateBadgeView = stateBadgeView {
            self.contentView.addSubview(stateBadgeView)
            
            if let imageView = imageView {
                stateBadgeView.centerXAnchor.constraint(equalTo: imageView.rightAnchor).isActive = true
                stateBadgeView.centerYAnchor.constraint(equalTo: imageView.bottomAnchor).isActive = true
            }
        }

        contentView.insertSubview(localDebProgressView, at: 0)
        NSLayoutConstraint.activate([
            localDebProgressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            localDebProgressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            localDebProgressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            localDebProgressView.heightAnchor.constraint(equalToConstant: 3)
        ])
        updateLocalDebProgressAppearance()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(localDebDownloadProgressDidChange(_:)),
                                               name: DownloadManager.localDebDownloadProgressNotification,
                                               object: nil)
    }
    
    @objc func updateSileoColors() {
        if !(targetPackage?.commercial ?? false) {
            titleLabel?.textColor = .sileoLabel
        }
        updateLocalDebProgressAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        localDebProgressView.isHidden = true
        localDebProgressView.setProgress(0, animated: false)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        var numberOfItemsInRow = CGFloat(1)
        if UIDevice.current.userInterfaceIdiom == .pad || UIApplication.shared.statusBarOrientation.isLandscape {
            numberOfItemsInRow = (self.superview?.bounds.width ?? 0) / 300
        }
        
        if alwaysHidesSeparator || !localDebProgressView.isHidden || ceil((item + 1) / numberOfItemsInRow) == ceil(numberOfItems / numberOfItemsInRow) {
            separatorView?.isHidden = true
        } else {
            separatorView?.isHidden = false
        }
    }
    
    func setTargetPackage(_ package: Package, isUnread: Bool) {
        self.targetPackage = package
        unreadView?.isHidden = !isUnread
    }
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        
        if targetPackage?.commercial ?? false {
            titleLabel?.textColor = self.tintColor
        }
        
        unreadView?.backgroundColor = self.tintColor
        updateLocalDebProgressAppearance()
    }
    
    @objc func refreshState() {
        applyLocalDebProgress()
        guard let targetPackage = targetPackage else {
            stateBadgeView?.isHidden = true
            return
        }
        stateBadgeView?.isHidden = false
        let queueState = DownloadManager.shared.find(package: targetPackage)
        switch queueState {
        case .installations:
            let isInstalled = PackageListManager.shared.installedPackage(identifier: targetPackage.packageID) != nil
            stateBadgeView?.state = isInstalled ? .reinstallQueued : .installQueued
        case .upgrades:
            stateBadgeView?.state = .updateQueued
        case .uninstallations:
            stateBadgeView?.state = .deleteQueued
        default:
            let isInstalled = PackageListManager.shared.installedPackage(identifier: targetPackage.packageID) != nil
            stateBadgeView?.state = .installed
            stateBadgeView?.isHidden = !isInstalled
        }
    }

    @objc private func localDebDownloadProgressDidChange(_ notification: Notification) {
        guard let package = targetPackage,
              let key = notification.object as? String,
              DownloadManager.shared.localDebDownloadKey(for: package) == key else { return }
        applyLocalDebProgress()
    }

    private func applyLocalDebProgress() {
        guard let package = targetPackage,
              let progress = DownloadManager.shared.localDebProgress(for: package) else {
            if !localDebProgressView.isHidden {
                localDebProgressView.isHidden = true
                localDebProgressView.setProgress(0, animated: false)
                setNeedsLayout()
            }
            return
        }
        let wasHidden = localDebProgressView.isHidden
        localDebProgressView.isHidden = false
        separatorView?.isHidden = true
        localDebProgressView.setProgress(Float(min(1, max(0, progress))), animated: !wasHidden && progress > 0)
        if wasHidden {
            setNeedsLayout()
        }
    }

    private func updateLocalDebProgressAppearance() {
        localDebProgressView.progressTintColor = SileoThemeManager.shared.tintColor
        localDebProgressView.trackTintColor = UIColor.sileoSeparatorColor
    }

}

extension PackageCollectionViewCell: SwipeCollectionViewCellDelegate {
    private func packageForInstallActions(from package: Package) -> Package {
        if package.package.contains("/") {
            return package
        }
        if package.sourceRepo != nil, package.filename != nil {
            return package
        }
        return PackageListManager.shared.newestPackage(identifier: package.package, repoContext: nil) ?? package
    }

    private func isDownloadablePackage(_ package: Package) -> Bool {
        if package.package.contains("/") {
            // Local deb imports do not have repo/filename metadata, but are installable.
            return true
        }
        return package.sourceRepo != nil && package.filename != nil
    }

    func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        // Different actions depending on where we are headed
        // Also making sure that the set package actually exists
        if let provisionalPackage = provisionalTarget {
            let repo = provisionalPackage.repository
            guard orientation == .right else { return nil }
            if !RepoManager.shared.hasRepo(with: repo.uri) {
                return [addRepo(provisionalPackage)]
            }
            return nil
        }
        guard let package = targetPackage,
              UserDefaults.standard.bool(forKey: "SwipeActions", fallback: true)  else { return nil }
        var actions = [SwipeAction]()
        let queueFound = DownloadManager.shared.find(package: package)
        // 右滑：取消队列、复制下载链接、下载 deb 到本地
        if orientation == .left {
            if queueFound != .none {
                actions.append(cancelAction(package))
            }
            let downloadPackage = packageForInstallActions(from: package)
            if canCopyOrDownload(downloadPackage) {
                // SwipeCellKit 最靠近 cell 的按钮排在数组末尾
                actions.append(downloadToLocalAction(downloadPackage))
                actions.append(copyDownloadURLAction(downloadPackage))
            }
            return actions.isEmpty ? nil : actions
        }
        // Check if the package is actually installed
        if let installedPackage = PackageListManager.shared.installedPackage(identifier: package.packageID) {
            let actionPackage = packageForInstallActions(from: package)
            // Check we have a repo for the package
            if queueFound != .uninstallations {
                actions.append(uninstallAction(package))
            }
            if isDownloadablePackage(actionPackage) {
                // Check if can be updated
                if DpkgWrapper.isVersion(actionPackage.version, greaterThan: installedPackage.version) {
                    if queueFound != .upgrades {
                        actions.append(upgradeAction(actionPackage))
                    }
                } else {
                    // Only add re-install if it can't be updated
                    if queueFound != .installations {
                        actions.append(reinstallAction(actionPackage))
                    }
                }
            }
        } else {
            if queueFound != .installations {
                actions.append(getAction(package))
            }
        }
        return actions
    }
    
    func collectionView(_ collectionView: UICollectionView, editActionsOptionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> SwipeOptions {
        var options = SwipeOptions()
        options.expansionStyle = .selection
        if #available(iOS 26.0, *) {
            options.backgroundColor = .clear
            options.buttonVerticalAlignment = .center
        }
        return options
    }

    private func configureSwipeAction(_ action: SwipeAction, backgroundColor: UIColor, image: UIImage?) {
        if #available(iOS 26.0, *) {
            action.backgroundColor = .clear
            action.image = nil
            action.font = .systemFont(ofSize: 15, weight: .medium)
            action.transitionDelegate = PackageSwipeActionTransition(backgroundColor: backgroundColor)
        } else {
            action.backgroundColor = backgroundColor
            action.image = image
        }
    }
    
    private func addRepo(_ package: ProvisionalPackage) -> SwipeAction {
        let addRepo = SwipeAction(style: .default, title: String(localizationKey: "Add_Source.Title")) { _, _ in
            if let tabBarController = self.window?.rootViewController as? UITabBarController,
               let sourcesNavNV = (tabBarController.sileoViewControllers?[2] as? SileoNavigationController) ??
                   (tabBarController.sileoViewControllers?[2] as? UISplitViewController)?.viewControllers[0] as? SileoNavigationController,
               let targetVC = tabBarController.sileoViewControllers?[2] {
                    tabBarController.sileoSelectedViewController = targetVC
                    if let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController {
                        sourcesVC.presentAddSourceEntryField(url: package.repository.uri)
                    }
            }
            if let package = CanisterResolver.package(package) {
                CanisterResolver.shared.queuePackage(package)
            }
            self.hapticResponse()
            self.hideSwipe(animated: true)
        }
        configureSwipeAction(addRepo,
                             backgroundColor: .systemPink,
                             image: UIImage(systemNameOrNil: "plus.app"))
        return addRepo
    }
    
    private func cancelAction(_ package: Package) -> SwipeAction {
        let cancel = SwipeAction(style: .destructive, title: String(localizationKey: "Cancel")) { _, _ in
            DownloadManager.shared.remove(package: package.packageID)
            DownloadManager.shared.reloadData(recheckPackages: true)
            self.hapticResponse()
            self.hideSwipe(animated: true)
        }
        configureSwipeAction(cancel,
                             backgroundColor: .systemRed,
                             image: UIImage(systemNameOrNil: "x.circle"))
        return cancel
    }

    private func canCopyOrDownload(_ package: Package) -> Bool {
        if package.package.contains("/") {
            return true
        }
        return package.sourceRepo != nil && !(package.filename ?? "").isEmpty
    }

    private func copyDownloadURLAction(_ package: Package) -> SwipeAction {
        let copy = SwipeAction(style: .default, title: String(localizationKey: "Package_Copy_Download_URL_Action")) { _, _ in
            self.hapticResponse()
            self.hideSwipe(animated: true)
            DownloadManager.shared.copyPackageDownloadURL(for: package) { errorMessage, urlString in
                if let urlString = urlString {
                    UIPasteboard.general.string = urlString
                    self.presentPackageAlert(title: String(localizationKey: "Package_Copy_Download_URL_Success"),
                                             message: nil)
                } else {
                    self.presentPackageAlert(title: String(localizationKey: "Unknown", type: .error),
                                             message: errorMessage)
                }
            }
        }
        configureSwipeAction(copy,
                             backgroundColor: .systemBlue,
                             image: UIImage(systemNameOrNil: "doc.on.doc"))
        return copy
    }

    private func downloadToLocalAction(_ package: Package) -> SwipeAction {
        let download = SwipeAction(style: .default, title: String(localizationKey: "Package_Download_Deb_Action")) { _, _ in
            self.hapticResponse()
            self.hideSwipe(animated: true)
            DownloadManager.shared.savePackageToDownloads(package) { errorMessage, fileURL in
                DispatchQueue.main.async {
                    if let fileURL = fileURL {
                        #if targetEnvironment(simulator) || TARGET_SANDBOX
                        self.presentSaveToFiles(fileURL)
                        #else
                        self.presentPackageAlert(title: String(localizationKey: "Package_Download_Deb_Success_Title"),
                                                 message: DownloadManager.packageDownloadSuccessMessage(for: fileURL),
                                                 fileURL: fileURL)
                        #endif
                    } else {
                        self.presentPackageAlert(title: String(localizationKey: "Unknown", type: .error),
                                                 message: errorMessage)
                    }
                }
            }
        }
        configureSwipeAction(download,
                             backgroundColor: .systemTeal,
                             image: UIImage(systemNameOrNil: "arrow.down.circle"))
        return download
    }
    
    private func uninstallAction(_ package: Package) -> SwipeAction {
        let uninstall = SwipeAction(style: .destructive, title: String(localizationKey: "Package_Uninstall_Action")) { _, _ in
            let queueFound = DownloadManager.shared.find(package: package)
            if queueFound != .none {
                DownloadManager.shared.remove(package: package.packageID)
            }
            DownloadManager.shared.add(package: package, queue: .uninstallations)
            DownloadManager.shared.reloadData(recheckPackages: true)
            self.hapticResponse()
            self.hideSwipe(animated: true)
        }
        configureSwipeAction(uninstall,
                             backgroundColor: .systemRed,
                             image: UIImage(systemNameOrNil: "trash.circle"))
        return uninstall
    }
    
    private func upgradeAction(_ package: Package) -> SwipeAction {
        let update = SwipeAction(style: .default, title: String(localizationKey: "Package_Upgrade_Action")) { _, _ in
            let queueFound = DownloadManager.shared.find(package: package)
            if queueFound != .none {
                DownloadManager.shared.remove(package: package.packageID)
            }
            DownloadManager.shared.add(package: package, queue: .upgrades)
            DownloadManager.shared.reloadData(recheckPackages: true)
            self.hapticResponse()
            self.hideSwipe(animated: true)
        }
        configureSwipeAction(update,
                             backgroundColor: .systemBlue,
                             image: UIImage(systemNameOrNil: "icloud.and.arrow.down"))
        return update
    }
    
    private func reinstallAction(_ package: Package) -> SwipeAction {
        let reinstall = SwipeAction(style: .default, title: String(localizationKey: "Package_Reinstall_Action")) { _, _ in
            let queueFound = DownloadManager.shared.find(package: package)
            if queueFound != .none {
                DownloadManager.shared.remove(package: package.packageID)
            }
            DownloadManager.shared.add(package: package, queue: .installations)
            DownloadManager.shared.reloadData(recheckPackages: true)
            self.hapticResponse()
            self.hideSwipe(animated: true)
        }
        configureSwipeAction(reinstall,
                             backgroundColor: .systemOrange,
                             image: UIImage(systemNameOrNil: "arrow.clockwise.circle"))
        return reinstall
    }

    private func getAction(_ package: Package) -> SwipeAction {
        let install = SwipeAction(style: .default, title: String(localizationKey: "Package_Get_Action")) { _, _ in
            let queueFound = DownloadManager.shared.find(package: package)
            if queueFound != .none {
                DownloadManager.shared.remove(package: package.packageID)
            }
            if package.sourceRepo != nil && !package.package.contains("/") {
                if !package.commercial {
                    DownloadManager.shared.add(package: package, queue: .installations)
                    DownloadManager.shared.reloadData(recheckPackages: true)
                } else {
                    self.updatePurchaseStatus(package) { error, provider, purchased in
                        guard let provider = provider else {
                            return self.presentAlert(paymentError: .invalidResponse,
                                                     title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title",
                                                                   type: .error))
                        }
                        if let error = error {
                            return self.presentAlert(paymentError: error,
                                                     title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title",
                                                                   type: .error))
                        }
                        if purchased {
                            DownloadManager.shared.add(package: package, queue: .installations)
                            DownloadManager.shared.reloadData(recheckPackages: true)
                        } else {
                            if provider.isAuthenticated {
                                self.initatePurchase(provider: provider, package: package)
                            } else {
                                DispatchQueue.main.async {
                                    self.authenticate(provider: provider, package: package)
                                }
                            }
                        }
                    }
                }
            }
            self.hapticResponse()
            self.hideSwipe(animated: true)
        }
        let image = package.commercial ? UIImage(systemNameOrNil: "dollarsign.circle") : UIImage(systemNameOrNil: "square.and.arrow.down")
        configureSwipeAction(install, backgroundColor: .systemGreen, image: image)
        return install
    }
        
    private func updatePurchaseStatus(_ package: Package, _ completion: ((PaymentError?, PaymentProvider?, Bool) -> Void)?) {
        guard let repo = package.sourceRepo else {
            return self.presentAlert(paymentError: .noPaymentProvider, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title",
                                                                                     type: .error))
        }
        PaymentManager.shared.getPaymentProvider(for: repo) { error, provider in
            guard let provider = provider else {
                if let completion = completion { completion(.noPaymentProvider, nil, false) }
                return
            }
            if error != nil { if let completion = completion { completion(error, provider, false) }; return }
            provider.getPackageInfo(forIdentifier: package.package) { error, info in
                guard let info = info else {
                    if let completion = completion { completion(error, provider, false) }
                    return
                }
                if error != nil {
                    return
                }
                if info.purchased {
                    DownloadManager.shared.add(package: package, queue: .installations)
                    DownloadManager.shared.reloadData(recheckPackages: true)
                    if let completion = completion {
                        completion(nil, provider, true)
                    }
                } else {
                    if let completion = completion {
                        completion(nil, provider, false)
                    }
                }
            }
        }
    }
    
    private func initatePurchase(provider: PaymentProvider, package: Package) {
        provider.initiatePurchase(forPackageIdentifier: package.package) { error, status, actionURL in
            if status == .cancel { return }
            guard !(error?.shouldInvalidate ?? false) else {
                return self.authenticate(provider: provider, package: package)
            }
            if error != nil || status == .failed {
                self.presentAlert(paymentError: error,
                                  title: String(localizationKey: "Purchase_Initiate_Fail.Title",
                                                type: .error))
            }
            guard let actionURL = actionURL,
                status != .immediateSuccess else {
                    return self.updatePurchaseStatus(package, nil)
            }
            DispatchQueue.main.async {
                PaymentAuthenticator.shared.handlePayment(actionURL: actionURL, provider: provider, window: self.window) { error, success in
                    if error != nil {
                        let title = String(localizationKey: "Purchase_Complete_Fail.Title", type: .error)
                        return self.presentAlert(paymentError: error, title: title)
                    }
                    if success {
                        self.updatePurchaseStatus(package, nil)
                    }
                }
            }
        }
    }
    
    private func authenticate(provider: PaymentProvider, package: Package) {
        PaymentAuthenticator.shared.authenticate(provider: provider, window: self.window) { error, success in
            if error != nil {
                return self.presentAlert(paymentError: error, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title",
                                                                            type: .error))
            }
            if success {
                self.updatePurchaseStatus(package, nil)
            }
        }
    }
    
    private func presentAlert(paymentError: PaymentError?, title: String) {
        DispatchQueue.main.async {
            self.presentingViewControllerForAlerts()?.presentSileoAlert(PaymentError.alert(for: paymentError, title: title),
                                                                        tintColor: .tintColor)
        }
    }

    private func presentingViewControllerForAlerts() -> UIViewController? {
        if let presenter = TabBarController.singleton {
            return topMostViewController(from: presenter)
        }
        guard let window = self.window ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first else {
            return nil
        }
        return topMostViewController(from: window.rootViewController)
    }

    private func topMostViewController(from root: UIViewController?) -> UIViewController? {
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        if let navigationController = current as? UINavigationController {
            return topMostViewController(from: navigationController.visibleViewController ?? navigationController.topViewController)
        }
        if let tabBarController = current as? UITabBarController {
            return topMostViewController(from: tabBarController.sileoSelectedViewController)
        }
        if let splitViewController = current as? UISplitViewController {
            return topMostViewController(from: splitViewController.viewControllers.last)
        }
        return current
    }

    private func presentSaveToFiles(_ fileURL: URL) {
        guard let presenter = presentingViewControllerForAlerts() else { return }
        LocalDebFilesExporter.present(fileURL: fileURL, from: presenter)
    }

    private func presentPackageAlert(title: String, message: String?, fileURL: URL? = nil) {
        let present = {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            #if !targetEnvironment(simulator) && !TARGET_SANDBOX
            if let fileURL = fileURL,
               let filzaURL = DownloadManager.filzaURL(for: fileURL),
               UIApplication.shared.canOpenURL(URL(string: "filza:///")!) {
                alert.addAction(UIAlertAction(title: String(localizationKey: "Open_In_Filza"), style: .default, handler: { _ in
                    UIApplication.shared.open(filzaURL)
                }))
            }
            #endif
            alert.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .default))
            let presenter = self.presentingViewControllerForAlerts()
            if #available(iOS 13.0, *) {
                switch SileoThemeManager.shared.currentTheme.preferredUserInterfaceStyle {
                case .light:
                    alert.overrideUserInterfaceStyle = .light
                case .dark:
                    alert.overrideUserInterfaceStyle = .dark
                default:
                    alert.overrideUserInterfaceStyle = presenter?.overrideUserInterfaceStyle ?? self.window?.overrideUserInterfaceStyle ?? .unspecified
                }
            }
            presenter?.presentSileoAlert(alert, tintColor: .tintColor)
        }
        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.async(execute: present)
        }
    }
    
    private func hapticResponse() {
        if #available(iOS 13, *) {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}


private final class LocalDebFilesExporter: NSObject, UIDocumentPickerDelegate {
    static var active: LocalDebFilesExporter?

    static func present(fileURL: URL, from presenter: UIViewController) {
        let exporter = LocalDebFilesExporter()
        active = exporter
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = exporter
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Self.active = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.active = nil
    }
}
