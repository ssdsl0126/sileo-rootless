//
//  PackageQueueButton.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

protocol PackageQueueButtonDataProvider: AnyObject {
    func updatePurchaseStatus()
}

class PackageQueueButton: PackageButton {
    public weak var viewControllerForPresentation: UIViewController?
    public var package: Package? {
        didSet {
            if package?.isProvisional ?? false {
                return self.updateButton(title: String(localizationKey: "Add_Source.Title"))
            }
            self.updatePurchaseStatus()
            self.updateInfo()
        }
    }

    private var _paymentInfo: PaymentPackageInfo?
    public var paymentInfo: PaymentPackageInfo? {
        get {
            _paymentInfo
        }
        set {
            _paymentInfo = shouldCheckPurchaseStatus ? newValue : nil
            self.updateInfo()
        }
    }
    
    public weak var dataProvider: PackageQueueButtonDataProvider? {
        didSet {
            self.updatePurchaseStatus()
        }
    }
    
    public var overrideTitle: String = ""
    public var shouldCheckPurchaseStatus = false
    
    private var purchased = false
    private var installedPackage: Package?
    
    override func setup() {
        super.setup()
        
        shouldCheckPurchaseStatus = true
        
        self.updateButton(title: String(localizationKey: "Package_Get_Action"))
        self.addTarget(self, action: #selector(PackageQueueButton.buttonTapped(_:)), for: .touchUpInside)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(PackageQueueButton.updateInfo),
                                               name: PackageListManager.stateChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(PackageQueueButton.updateInfo),
                                               name: DownloadManager.lockStateChangeNotification,
                                               object: nil)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(PackageQueueButton.showDowngradePrompt(_:)))
        self.addGestureRecognizer(longPressGesture)
    }

    @objc func showDowngradePrompt(_ sender: Any?) {
        guard let package = package,
            (!package.commercial || purchased) else {
            return
        }
        let downgradePrompt = UIAlertController(title: String(localizationKey: "Select Version"),
                                                message: String(localizationKey: "Select the version of the package to install"),
                                                preferredStyle: .actionSheet)
        var allVersions = [Package]()
        if package.fromStatusFile {
            for repo in RepoManager.shared.repoList {
                allVersions += repo.allVersions(identifier: package.package, ignoreArch: true)
            }
            allVersions = PackageListManager.shared.sortPackages(packages: allVersions, search: nil)
        } else {
            allVersions = package.allVersions(ignoreArch: true).sorted(by: { obj1, obj2 -> Bool in
                DpkgWrapper.isVersion(obj1.version, greaterThan: obj2.version)
            })
        }
        
        for versionPackage in allVersions {
            if (versionPackage.sourceRepo?.rawURL.hasPrefix("https://") == true ||
                versionPackage.sourceRepo?.rawURL.hasPrefix("http://") == true)
                && versionPackage.filename != nil && versionPackage.size != nil {
                downgradePrompt.addAction(UIAlertAction(title: versionPackage.version, style: .default, handler: { (_: UIAlertAction) in
                    let downloadManager = DownloadManager.shared
                    let queueFound = downloadManager.find(package: versionPackage)
                    if queueFound != .none {
                        // but it's a already queued! user changed their mind about installing this new package => nuke it from the queue
                        downloadManager.remove(package: versionPackage, queue: queueFound)
                    }

                    downloadManager.add(package: versionPackage, queue: .installations)
                    downloadManager.reloadData(recheckPackages: true)
                }))
            }
         }

        let cancelAction = UIAlertAction(title: String(localizationKey: "Package_Cancel_Action"), style: .cancel, handler: nil)
        downgradePrompt.addAction(cancelAction)
        if UIDevice.current.userInterfaceIdiom == .pad {
            downgradePrompt.popoverPresentationController?.sourceView = self
        }
        let tintColor = self.tintColor
        downgradePrompt.view.tintColor = tintColor
        viewControllerForPresentation?.present(downgradePrompt, animated: true, completion: {
            downgradePrompt.view.tintColor = tintColor
        })
    }
    
    @objc func updateInfo() {
        guard let package = package else {
            self.isEnabled = false
            return
        }
        installedPackage = PackageListManager.shared.installedPackage(identifier: package.package)
            
        purchased = paymentInfo?.purchased ?? false
        
        let queueFound = DownloadManager.shared.find(package: package)
        var prominent = false
        if !overrideTitle.isEmpty {
            self.updateButton(title: overrideTitle)
        } else if queueFound != .none {
            self.updateButton(title: String(localizationKey: "Package_Queue_Action"))
        } else if installedPackage != nil {
            self.updateButton(title: String(localizationKey: "Package_Modify_Action"))
        } else if let price = paymentInfo?.price,
            package.commercial && !purchased {
            self.updateButton(title: price)
        } else {
            self.updateButton(title: String(localizationKey: "Package_Get_Action"))
            prominent = true
        }
        
        self.isProminent = prominent
        self.isEnabled = !DownloadManager.shared.lockedForInstallation
    }
    
    func updatePurchaseStatus() {
        guard let dataProvider = dataProvider,
            shouldCheckPurchaseStatus,
            package?.commercial ?? false,
            !(package?.package.contains("/") ?? false) else {
                return
        }
        DispatchQueue.main.async {
            self.isEnabled = false
            dataProvider.updatePurchaseStatus()
        }
    }
    
    func updateButton(title: String) {
        self.setTitle(title.uppercased(), for: .normal)
    }

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
        package.sourceRepo != nil && package.filename != nil
    }
    
    func actionItems() -> [CSActionItem] {
        guard let package = self.package else {
                return []
        }
        if package.isProvisional ?? false {
            guard let source = package.source else {
                return []
            }
            let action = CSActionItem(title: String(localizationKey: "Add_Source.Title"),
                                      image: UIImage(systemNameOrNil: "square.and.arrow.down"),
                                      style: .default) {
                self.hapticResponse()
                self.addRepo(source)
                CanisterResolver.shared.queuePackage(package)
            }
            return [action]
        }
        var actionItems: [CSActionItem] = []

        let downloadManager = DownloadManager.shared

        let queueFound = downloadManager.find(package: package)
        if let installedPackage = installedPackage {
            let actionPackage = packageForInstallActions(from: package)
            if !package.commercial || (paymentInfo?.available ?? false) {
                if isDownloadablePackage(actionPackage) {
                    if DpkgWrapper.isVersion(actionPackage.version, greaterThan: installedPackage.version) {
                        let action = CSActionItem(title: String(localizationKey: "Package_Upgrade_Action"),
                                                  image: UIImage(systemNameOrNil: "icloud.and.arrow.down"),
                                                  style: .default) {
                            if queueFound != .none {
                                downloadManager.remove(package: package, queue: queueFound)
                            }
                            self.hapticResponse()
                            downloadManager.add(package: actionPackage, queue: .upgrades)
                            downloadManager.reloadData(recheckPackages: true)
                        }
                        actionItems.append(action)
                    } else if actionPackage.version == installedPackage.version {
                        let action = CSActionItem(title: String(localizationKey: "Package_Reinstall_Action"),
                                                  image: UIImage(systemNameOrNil: "arrow.clockwise.circle"),
                                                  style: .default) {
                            if queueFound != .none {
                                downloadManager.remove(package: package, queue: queueFound)
                            }
                            self.hapticResponse()
                            downloadManager.add(package: actionPackage, queue: .installations)
                            downloadManager.reloadData(recheckPackages: true)
                        }
                        actionItems.append(action)
                    }
                }
            }
            let action = CSActionItem(title: String(localizationKey: "Package_Uninstall_Action"),
                                      image: UIImage(systemNameOrNil: "trash.circle"),
                                      style: .destructive) {
                self.hapticResponse()
                downloadManager.add(package: package, queue: .uninstallations)
                downloadManager.reloadData(recheckPackages: true)
            }
            actionItems.append(action)
        } else {
            // here's new packages not yet queued
            if let repo = package.sourceRepo,
                package.commercial && !purchased {
                let buttonText = paymentInfo?.price ?? String(localizationKey: "Package_Get_Action")
                let action = CSActionItem(title: buttonText,
                                          image: UIImage(systemNameOrNil: "dollarsign.circle"),
                                          style: .default) {
                    self.hapticResponse()
                    PaymentManager.shared.getPaymentProvider(for: repo) { error, provider in
                        guard let provider = provider,
                            error == nil else {
                                return
                        }
                        if provider.isAuthenticated {
                            self.initatePurchase(provider: provider)
                        } else {
                            self.authenticate(provider: provider)
                        }
                    }
                }
                actionItems.append(action)
            } else {
                let action = CSActionItem(title: String(localizationKey: "Package_Get_Action"),
                                          image: UIImage(systemNameOrNil: "square.and.arrow.down"),
                                          style: .default) {
                    // here's new packages not yet queued & FREE
                    self.hapticResponse()
                    downloadManager.add(package: package, queue: .installations)
                    downloadManager.reloadData(recheckPackages: true)
                }
                actionItems.append(action)
            }
        }
        let copyBundleIDAction = CSActionItem(title: String(localizationKey: "Copy_ID"), image: .init(systemNameOrNil: "doc.on.doc"), style: .default) {
            UIPasteboard.general.string = package.packageID
        }
        actionItems.append(copyBundleIDAction)
        
        return actionItems
    }
    
    private func addRepo(_ url: URL) {
        if let tabBarController = self.window?.rootViewController as? UITabBarController,
            let sourcesSVC = tabBarController.viewControllers?[2] as? UISplitViewController,
              let sourcesNavNV = sourcesSVC.viewControllers[0] as? SileoNavigationController {
              tabBarController.selectedViewController = sourcesSVC
              if let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController {
                sourcesVC.presentAddSourceEntryField(url: url)
              }
        }
    }
    
    private func handleButtonPress(_ package: Package, _ check: Bool = true) {
        if check {
            if package.isProvisional ?? false {
                guard let source = package.source else { return }
                self.addRepo(source)
                CanisterResolver.shared.queuePackage(package)
                return
            }
        }
        self.hapticResponse()
        let downloadManager = DownloadManager.shared
        let queueFound = downloadManager.find(package: package)
        if queueFound != .none {
            // but it's a already queued! user changed their mind about installing this new package => nuke it from the queue
            TabBarController.singleton?.presentPopupController()
            downloadManager.reloadData(recheckPackages: true)
        } else if let installedPackage = installedPackage {
            let actionPackage = packageForInstallActions(from: package)
            // road clear to modify an installed package, now we gotta decide what modification
            let downloadPopup: UIAlertController! = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            if !package.commercial || (paymentInfo?.available ?? false) {
                if isDownloadablePackage(actionPackage) {
                    if DpkgWrapper.isVersion(actionPackage.version, greaterThan: installedPackage.version) {
                        let upgradeAction = UIAlertAction(title: String(localizationKey: "Package_Upgrade_Action"),
                                                          style: .default) { _ in
                            downloadManager.add(package: actionPackage, queue: .upgrades)
                            downloadManager.reloadData(recheckPackages: true)
                        }
                        downloadPopup.addAction(upgradeAction)
                    } else if actionPackage.version == installedPackage.version {
                        let reinstallAction = UIAlertAction(title: String(localizationKey: "Package_Reinstall_Action"),
                                                            style: .default) { _ in
                            downloadManager.add(package: actionPackage, queue: .installations)
                            downloadManager.reloadData(recheckPackages: true)
                        }
                        downloadPopup.addAction(reinstallAction)
                    }
                }
            }

            let removeAction = UIAlertAction(title: String(localizationKey: "Package_Uninstall_Action"), style: .default, handler: { _ in
                downloadManager.add(package: package, queue: .uninstallations)
                downloadManager.reloadData(recheckPackages: true)
            })
            downloadPopup.addAction(removeAction)
            let cancelAction: UIAlertAction! = UIAlertAction(title: String(localizationKey: "Package_Cancel_Action"), style: .cancel)
            downloadPopup.addAction(cancelAction)
            if UIDevice.current.userInterfaceIdiom == .pad {
                downloadPopup.popoverPresentationController?.sourceView = self
            }
            let tintColor: UIColor! = self.tintColor
            if tintColor != nil {
                downloadPopup.view.tintColor = tintColor
            }
            self.viewControllerForPresentation?.present(downloadPopup, animated: true, completion: {
                if tintColor != nil {
                    downloadPopup.view.tintColor = tintColor
                }
            })
        } else {
            // here's new packages not yet queued
            if let repo = package.sourceRepo,
                package.commercial && !purchased && !package.package.contains("/") {
                PaymentManager.shared.getPaymentProvider(for: repo) { error, provider in
                    guard let provider = provider,
                        error == nil else {
                            return
                    }
                    if provider.isAuthenticated {
                        self.initatePurchase(provider: provider)
                    } else {
                        self.authenticate(provider: provider)
                    }
                }
            } else {
                // here's new packages not yet queued & FREE
                downloadManager.add(package: package, queue: .installations)
                downloadManager.reloadData(recheckPackages: true)
            }
        }
    }
    
    @objc func buttonTapped(_ sender: Any?) {
        guard let package = self.package else {
            return
        }
        self.handleButtonPress(package)
    }
    
    private func initatePurchase(provider: PaymentProvider) {
        guard let package = package else {
            return
        }
        provider.initiatePurchase(forPackageIdentifier: package.package) { error, status, actionURL in
            if status == .cancel { return }
            guard !(error?.shouldInvalidate ?? false) else {
                return self.authenticate(provider: provider)
            }
            if error != nil || status == .failed {
                self.presentAlert(paymentError: error,
                                  title: String(localizationKey: "Purchase_Initiate_Fail.Title",
                                                type: .error))
            }
            guard let actionURL = actionURL,
                status != .immediateSuccess else {
                    return self.updatePurchaseStatus()
            }
            DispatchQueue.main.async {
                PaymentAuthenticator.shared.handlePayment(actionURL: actionURL, provider: provider, window: self.window) { error, success in
                    if error != nil {
                        let title = String(localizationKey: "Purchase_Complete_Fail.Title", type: .error)
                        return self.presentAlert(paymentError: error, title: title)
                    }
                    if success {
                        self.updatePurchaseStatus()
                    }
                }
            }
        }
    }
    
    private func authenticate(provider: PaymentProvider) {
        PaymentAuthenticator.shared.authenticate(provider: provider, window: self.window) { error, success in
            if error != nil {
                return self.presentAlert(paymentError: error, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title",
                                                                            type: .error))
            }
            if success {
                self.updatePurchaseStatus()
            }
        }
    }
    
    private func presentAlert(paymentError: PaymentError?, title: String) {
        DispatchQueue.main.async {
            self.viewControllerForPresentation?.present(PaymentError.alert(for: paymentError, title: title),
                                                        animated: true,
                                                        completion: nil)
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
