//
//  DownloadsTableViewController.swift
//  Sileo
//
//  Created by CoolStar on 8/3/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit
import Evander

class DownloadsTableViewController: SileoViewController {
    @IBOutlet var footerView: UIView?
    @IBOutlet var cancelButton: UIButton?
    @IBOutlet var confirmButton: UIButton?
    @IBOutlet var footerViewHeight: NSLayoutConstraint?
    @IBOutlet var tableView: UITableView?
    @IBOutlet private var tableLeadingConstraint: NSLayoutConstraint?
    @IBOutlet private var tableTrailingConstraint: NSLayoutConstraint?
    @IBOutlet private var footerLeadingConstraint: NSLayoutConstraint?
    @IBOutlet private var footerTrailingConstraint: NSLayoutConstraint?
    
    @IBOutlet var detailsView: UIView?
    @IBOutlet var detailsTextView: UITextView?
    @IBOutlet var completeButton: DownloadConfirmButton?
    @IBOutlet var showDetailsButton: UIButton?
    @IBOutlet var hideDetailsButton: DownloadConfirmButton?
    @IBOutlet var completeLaterButton: DownloadConfirmButton?
    @IBOutlet var doneToTop: NSLayoutConstraint?
    @IBOutlet var laterHeight: NSLayoutConstraint?
    @IBOutlet var cancelDownload: DownloadConfirmButton?
    
    var transitionController = false
    var statusBarView: UIView?
    
    var upgrades: [DownloadPackage] = []
    var installations: [DownloadPackage] = []
    var uninstallations: [DownloadPackage] = []
    var installdeps: [DownloadPackage] = []
    var uninstalldeps: [DownloadPackage] = []
    var errors: ContiguousArray<APTBrokenPackage> = []
    
    private var actions = [InstallOperation]()
    private var isFired = false
    private var isInstalling = false
    public var isDownloading = false
    private var isFinishedInstalling = false
    private var returnButtonAction: APTWrapper.FINISH = .back
    private var refreshSileo = false
    private var hasErrored = false
    private var detailsAttributedString: NSMutableAttributedString?
    public var backgroundCallback: (() -> Void)?
    private var sheetBackdropView: UIView?
    private var sheetBackdropTopConstraint: NSLayoutConstraint?
    private var sheetCardContainerView: UIView?
    private var sheetCardEffectView: UIVisualEffectView?
    private var sheetCardTopConstraint: NSLayoutConstraint?
    private var sheetCardWidthConstraint: NSLayoutConstraint?
    private var installStatusContainerView: UIView?
    private var installStatusTextView: UITextView?
    private var installStatusEntries: [String] = []
    private var floatingContentHorizontalInset: CGFloat = 0
    private var floatingContentVerticalOffset: CGFloat = 0
    
    private let cardMaxWidthPad: CGFloat = 720
    private let sideMarginMin: CGFloat = 16
    private let floatingCornerRadius: CGFloat = 18
    public var usesSystemQueueSheetPresentation = false {
        didSet {
            DispatchQueue.main.async {
                self.updateQueueSheetHandle()
                self.applyFloatingLayoutMetrics(preserveTopPin: true)
            }
        }
    }
    private var queueSheetHandleView: UIView?
    private var queueSheetHandleLayer: CAShapeLayer?
    
    private var supportsFloatingSheetChrome: Bool {
        false
    }
    
    private var floatingSheetVerticalOffset: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return max(24, view.safeAreaInsets.top + 4)
        }
        return max(20, view.safeAreaInsets.top - 8)
    }
    
    private var floatingSheetTopInset: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return max(44, view.safeAreaInsets.top + 10)
        }
        return max(12, floatingContentVerticalOffset - 6)
    }
    
    private var floatingSheetHorizontalInset: CGFloat {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return 0
        }
        let safeWidth = view.safeAreaLayoutGuide.layoutFrame.width
        let targetWidth = min(cardMaxWidthPad, max(0, safeWidth - 32))
        return max(sideMarginMin, (safeWidth - targetWidth) / 2)
    }
    
    public class InstallOperation {
        
        // swiftlint:disable nesting
        public enum Operation {
            case install
            case removal
        }
        
        var package: Package
        var operation: Operation
        var progressCounter: CGFloat = 0.0
        var status: String?
        weak var cell: DownloadsTableViewCell?
        
        public var progress: CGFloat {
            let progress = progressCounter / (operation == .install ? 6.0 : 3.0)
            if progress > 1.0 {
                return 1.0
            } else {
                return progress
            }
        }
        
        init(package: Package, operation: Operation) {
            self.package = package
            self.operation = operation
            self.progressCounter = 0.0
        }
        
    }
    
    public override var prefersStatusBarHidden: Bool {
        return isFired
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        applyQueueNavigationBarAppearance()
        
        let statusBarView = SileoRootView(frame: .zero)
        self.view.addSubview(statusBarView)
        self.statusBarView = statusBarView
        
        self.statusBarStyle = .default
        
        self.tableView?.separatorStyle = .none
        self.tableView?.separatorColor = UIColor(red: 234/255, green: 234/255, blue: 236/255, alpha: 1)
        self.tableView?.isEditing = true
        self.tableView?.clipsToBounds = true
        self.tableView?.backgroundColor = .sileoBackgroundColor
        self.tableView?.isOpaque = true
        self.tableView?.contentInsetAdjustmentBehavior = .never
        if #available(iOS 15.0, *) {
            self.tableView?.sectionHeaderTopPadding = 0
        }
        
        confirmButton?.layer.cornerRadius = 10
        
        confirmButton?.setTitle(String(localizationKey: "Queue_Confirm_Button"), for: .normal)
        cancelButton?.setTitle(String(localizationKey: "Queue_Clear_Button"), for: .normal)
        completeButton?.setTitle(String(localizationKey: "After_Install_Respring"), for: .normal)
        completeLaterButton?.setTitle(String(localizationKey: "After_Install_Respring_Later"), for: .normal)
        showDetailsButton?.setTitle(String(localizationKey: "Show_Install_Details"), for: .normal)
        hideDetailsButton?.setTitle(String(localizationKey: "Hide_Install_Details"), for: .normal)
        cancelDownload?.setTitle(String(localizationKey: "Queue_Cancel_Downloads"), for: .normal)
        
        completeButton?.layer.cornerRadius = 10
        completeLaterButton?.layer.cornerRadius = 10
        hideDetailsButton?.layer.cornerRadius = 10
        cancelDownload?.layer.cornerRadius = 10
        showDetailsButton?.isHidden = true
        
        detailsTextView?.isScrollEnabled = true
        detailsTextView?.alwaysBounceVertical = true
        
        tableView?.register(DownloadsTableViewCell.self, forCellReuseIdentifier: "DownloadsTableViewCell")
        updateQueueSheetHandle()
        applyFloatingLayoutMetrics(preserveTopPin: false)
        updateFloatingSheetChrome()
        DownloadManager.shared.reloadData(recheckPackages: false)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateQueueSheetHandlePath()
        applyFloatingLayoutMetrics(preserveTopPin: true)
        updateFloatingSheetChrome()
        updateFloatingCardShadowPath()
        updateDetailsViewFrameIfNeeded()
        
        guard let tableView = self.tableView,
            let cancelButton = self.cancelButton,
            let confirmButton = self.confirmButton,
            let statusBarView = self.statusBarView else {
                return
        }
        
        statusBarView.frame = CGRect(origin: .zero,
                         size: CGSize(width: self.view.bounds.width,
                              height: max(tableView.safeAreaInsets.top, tableView.contentInset.top)))
        statusBarView.isHidden = supportsFloatingSheetChrome && UIDevice.current.userInterfaceIdiom != .phone
        statusBarView.backgroundColor = .sileoBackgroundColor
        
        cancelButton.tintColor = confirmButton.tintColor
        cancelButton.isHighlighted = confirmButton.isHighlighted
        confirmButton.tintColor = UINavigationBar.appearance().tintColor
        confirmButton.isHighlighted = confirmButton.isHighlighted
        
        completeButton?.tintColor = UINavigationBar.appearance().tintColor
        completeButton?.isHighlighted = completeButton?.isHighlighted ?? false
        cancelDownload?.tintColor = UINavigationBar.appearance().tintColor
        cancelDownload?.isHighlighted = completeButton?.isHighlighted ?? false
        completeLaterButton?.tintColor = .clear
        completeLaterButton?.isHighlighted = completeLaterButton?.isHighlighted ?? false
        completeLaterButton?.setTitleColor(UINavigationBar.appearance().tintColor, for: .normal)
 
        hideDetailsButton?.tintColor = UINavigationBar.appearance().tintColor
        hideDetailsButton?.isHighlighted = hideDetailsButton?.isHighlighted ?? false
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyQueueNavigationBarAppearance()
        updateQueueSheetHandlePath()
        applyFloatingLayoutMetrics(preserveTopPin: true)
        updateFloatingSheetChrome()
        updateFloatingCardShadowPath()
        updateDetailsViewFrameIfNeeded()
    }

    private func applyQueueNavigationBarAppearance() {
        guard let navigationBar = navigationController?.navigationBar else {
            return
        }

        navigationBar.isTranslucent = false

        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .sileoBackgroundColor
            appearance.shadowColor = .sileoSeparatorColor
            appearance.titleTextAttributes = navigationBar.standardAppearance.titleTextAttributes
            appearance.largeTitleTextAttributes = navigationBar.standardAppearance.largeTitleTextAttributes
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.compactScrollEdgeAppearance = appearance
        } else {
            navigationBar.barTintColor = .sileoBackgroundColor
        }
    }
    
    private func applyFloatingLayoutMetrics(preserveTopPin: Bool) {
        guard let tableView = tableView else {
            return
        }
        
        let verticalOffset = supportsFloatingSheetChrome ? floatingSheetVerticalOffset : 0
        let horizontalInset = supportsFloatingSheetChrome ? floatingSheetHorizontalInset : 0
        
        floatingContentVerticalOffset = verticalOffset
        floatingContentHorizontalInset = horizontalInset
        
        tableLeadingConstraint?.constant = horizontalInset
        tableTrailingConstraint?.constant = horizontalInset
        footerLeadingConstraint?.constant = horizontalInset
        footerTrailingConstraint?.constant = horizontalInset
        
        let newTopInset: CGFloat
        if usesSystemQueueSheetPresentation && UIDevice.current.userInterfaceIdiom == .phone {
            newTopInset = 43
        } else if supportsFloatingSheetChrome {
            newTopInset = 43 + verticalOffset
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            newTopInset = 43
        } else {
            newTopInset = 0
        }
        let oldTopInset = tableView.contentInset.top
        let wasPinnedToTop = preserveTopPin && abs(tableView.contentOffset.y + oldTopInset) < 1
        
        var contentInset = tableView.contentInset
        contentInset.top = newTopInset
        tableView.contentInset = contentInset
        
        var scrollIndicatorInsets = tableView.scrollIndicatorInsets
        scrollIndicatorInsets.top = newTopInset
        tableView.scrollIndicatorInsets = scrollIndicatorInsets
        
        if wasPinnedToTop && abs(oldTopInset - newTopInset) > 0.5 {
            tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x, y: -newTopInset), animated: false)
        }
    }

    private func updateQueueSheetHandle() {
        let shouldShow = usesSystemQueueSheetPresentation && UIDevice.current.userInterfaceIdiom == .phone
        if !shouldShow {
            queueSheetHandleView?.removeFromSuperview()
            queueSheetHandleView = nil
            queueSheetHandleLayer = nil
            return
        }

        let handleView: UIView
        if let existing = queueSheetHandleView {
            handleView = existing
        } else {
            let createdView = UIView()
            createdView.translatesAutoresizingMaskIntoConstraints = false
            createdView.backgroundColor = .clear
            view.addSubview(createdView)
            NSLayoutConstraint.activate([
                createdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                createdView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
                createdView.widthAnchor.constraint(equalToConstant: 42),
                createdView.heightAnchor.constraint(equalToConstant: 16)
            ])

            let shapeLayer = CAShapeLayer()
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.strokeColor = UIColor.systemGray2.cgColor
            shapeLayer.lineWidth = 3.5
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            createdView.layer.addSublayer(shapeLayer)

            queueSheetHandleLayer = shapeLayer
            queueSheetHandleView = createdView
            handleView = createdView
        }
        view.bringSubviewToFront(handleView)
        updateQueueSheetHandlePath()
    }

    private func updateQueueSheetHandlePath() {
        guard let handleView = queueSheetHandleView,
              let shapeLayer = queueSheetHandleLayer
        else {
            return
        }

        shapeLayer.frame = handleView.bounds
        let path = UIBezierPath()
        let midX = handleView.bounds.midX
        path.move(to: CGPoint(x: midX - 12, y: 5))
        path.addLine(to: CGPoint(x: midX, y: 10.5))
        path.addLine(to: CGPoint(x: midX + 12, y: 5))
        shapeLayer.path = path.cgPath
    }
    
    private func floatingDetailsFrame() -> CGRect {
        let safeFrame = view.safeAreaLayoutGuide.layoutFrame
        let width = max(0, safeFrame.width - floatingContentHorizontalInset * 2)
        let x = safeFrame.minX + floatingContentHorizontalInset
        let y = floatingSheetTopInset
        let height = max(0, view.bounds.height - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func resolvedFloatingCornerRadius() -> CGFloat {
        let candidates: [CGFloat] = [
            view.layer.cornerRadius,
            view.superview?.layer.cornerRadius ?? 0,
            view.superview?.superview?.layer.cornerRadius ?? 0
        ]
        let inheritedCornerRadius = candidates.max() ?? 0
        return inheritedCornerRadius > 0 ? inheritedCornerRadius : floatingCornerRadius
    }
    
    private func updateDetailsViewFrameIfNeeded() {
        guard let detailsView = detailsView,
              detailsView.superview === view
        else {
            return
        }
        detailsView.frame = supportsFloatingSheetChrome ? floatingDetailsFrame() : view.bounds
    }
    
    private func clearFloatingSheetChrome() {
        sheetBackdropView?.removeFromSuperview()
        sheetBackdropView = nil
        sheetBackdropTopConstraint = nil
        sheetCardContainerView?.removeFromSuperview()
        sheetCardContainerView = nil
        sheetCardEffectView?.removeFromSuperview()
        sheetCardEffectView = nil
        sheetCardTopConstraint = nil
        sheetCardWidthConstraint = nil
        
        view.backgroundColor = .sileoBackgroundColor
        statusBarView?.backgroundColor = .sileoBackgroundColor
        statusBarView?.isHidden = false
    }
    
    private func updateFloatingCardShadowPath() {
        guard let cardContainer = sheetCardContainerView,
              cardContainer.bounds.width > 0,
              cardContainer.bounds.height > 0
        else {
            return
        }
        let cornerRadius = resolvedFloatingCornerRadius()
        let path = UIBezierPath(
            roundedRect: cardContainer.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        )
        cardContainer.layer.shadowPath = path.cgPath
    }
    
    private func updateFloatingSheetChrome() {
        guard supportsFloatingSheetChrome else {
            clearFloatingSheetChrome()
            return
        }
        
        view.backgroundColor = .clear
        
        let backdropView: UIView
        if let existingBackdropView = sheetBackdropView {
            backdropView = existingBackdropView
        } else {
            let createdView = UIView()
            createdView.translatesAutoresizingMaskIntoConstraints = false
            createdView.isUserInteractionEnabled = false
            view.insertSubview(createdView, at: 0)
            let topConstraint = createdView.topAnchor.constraint(equalTo: view.topAnchor, constant: floatingSheetTopInset)
            sheetBackdropTopConstraint = topConstraint
            NSLayoutConstraint.activate([
                topConstraint,
                createdView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                createdView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                createdView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            sheetBackdropView = createdView
            backdropView = createdView
        }
        sheetBackdropTopConstraint?.constant = floatingSheetTopInset
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(UIColor.isDarkModeEnabled ? 0.14 : 0.08)
        
        let cardContainer: UIView
        if let existingCardContainer = sheetCardContainerView {
            cardContainer = existingCardContainer
        } else {
            let createdContainer = UIView()
            createdContainer.translatesAutoresizingMaskIntoConstraints = false
            createdContainer.isUserInteractionEnabled = false
            createdContainer.backgroundColor = .clear
            view.insertSubview(createdContainer, aboveSubview: backdropView)
            let topConstraint = createdContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: floatingSheetTopInset)
            let widthConstraint = createdContainer.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -(floatingContentHorizontalInset * 2))
            sheetCardTopConstraint = topConstraint
            sheetCardWidthConstraint = widthConstraint
            NSLayoutConstraint.activate([
                topConstraint,
                widthConstraint,
                createdContainer.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                createdContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            sheetCardContainerView = createdContainer
            cardContainer = createdContainer
        }
        
        let cardView: UIVisualEffectView
        if let existingCardView = sheetCardEffectView {
            cardView = existingCardView
        } else {
            let createdView = UIVisualEffectView(effect: nil)
            createdView.translatesAutoresizingMaskIntoConstraints = false
            createdView.isUserInteractionEnabled = false
            cardContainer.addSubview(createdView)
            NSLayoutConstraint.activate([
                createdView.topAnchor.constraint(equalTo: cardContainer.topAnchor),
                createdView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
                createdView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
                createdView.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor)
            ])
            sheetCardEffectView = createdView
            cardView = createdView
        }
        
        sheetCardTopConstraint?.constant = floatingSheetTopInset
        sheetCardWidthConstraint?.constant = -(floatingContentHorizontalInset * 2)
        let cornerRadius = resolvedFloatingCornerRadius()
        
        if #available(iOS 13.0, *) {
            cardView.effect = UIBlurEffect(style: .systemMaterial)
        } else {
            cardView.effect = UIBlurEffect(style: .light)
        }
        cardView.backgroundColor = UIColor.sileoBackgroundColor.withAlphaComponent(UIColor.isDarkModeEnabled ? 0.05 : 0.08)
        cardView.layer.cornerRadius = cornerRadius
        if #available(iOS 13.0, *) {
            cardView.layer.cornerCurve = .continuous
        }
        cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.layer.masksToBounds = true
        cardView.layer.borderWidth = 0.5
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(UIColor.isDarkModeEnabled ? 0.08 : 0.22).cgColor
        
        cardContainer.layer.cornerRadius = cornerRadius
        if #available(iOS 13.0, *) {
            cardContainer.layer.cornerCurve = .continuous
        }
        cardContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardContainer.layer.masksToBounds = false
        cardContainer.layer.shadowColor = UIColor.black.cgColor
        cardContainer.layer.shadowOpacity = 0
        cardContainer.layer.shadowRadius = 0
        cardContainer.layer.shadowOffset = .zero
        cardContainer.layer.shadowPath = nil
        
        if let tableView = tableView {
            view.bringSubviewToFront(tableView)
        }
        if let footerView = footerView {
            view.bringSubviewToFront(footerView)
        }
        if let statusBarView = statusBarView {
            view.bringSubviewToFront(statusBarView)
            if UIDevice.current.userInterfaceIdiom == .phone {
                statusBarView.backgroundColor = .black
                statusBarView.isHidden = false
            } else {
                statusBarView.backgroundColor = .sileoBackgroundColor
                statusBarView.isHidden = true
            }
        }
    }

    private func ensureInstallStatusContainer() {
        if installStatusContainerView != nil {
            return
        }
        let statusContainer = UIView()
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.backgroundColor = .clear
        statusContainer.isUserInteractionEnabled = true
        statusContainer.alpha = 0
        statusContainer.isHidden = true
        view.addSubview(statusContainer)
        
        let statusTextView = UITextView()
        statusTextView.translatesAutoresizingMaskIntoConstraints = false
        statusTextView.backgroundColor = .clear
        statusTextView.textColor = .sileoLabel
        statusTextView.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        statusTextView.textAlignment = .center
        statusTextView.isEditable = false
        statusTextView.isSelectable = false
        statusTextView.isScrollEnabled = true
        statusTextView.alwaysBounceVertical = true
        statusTextView.showsVerticalScrollIndicator = false
        statusTextView.showsHorizontalScrollIndicator = false
        statusTextView.textContainer.lineBreakMode = .byTruncatingTail
        statusTextView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        statusTextView.textContainer.lineFragmentPadding = 0
        statusContainer.addSubview(statusTextView)
        let preferredWidthConstraint = statusContainer.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -80)
        preferredWidthConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            statusContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            preferredWidthConstraint,
            statusContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            statusContainer.heightAnchor.constraint(equalToConstant: 180),
            statusTextView.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            statusTextView.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            statusTextView.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
            statusTextView.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor)
        ])
        installStatusTextView = statusTextView
        installStatusContainerView = statusContainer
    }
    
    private func setInstallStatusVisible(_ visible: Bool) {
        ensureInstallStatusContainer()
        guard let statusContainer = installStatusContainerView else { return }
        
        if visible {
            statusContainer.isHidden = false
            statusContainer.alpha = 0
            statusContainer.transform = CGAffineTransform(translationX: 0, y: 12)
            view.bringSubviewToFront(statusContainer)
            if let footerView = footerView {
                view.bringSubviewToFront(footerView)
            }
            FRUIView.animate(withDuration: 0.28, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
                self.tableView?.alpha = 0
                statusContainer.alpha = 1
                statusContainer.transform = .identity
            })
            return
        }
        
        FRUIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
            self.tableView?.alpha = 1
            statusContainer.alpha = 0
            statusContainer.transform = CGAffineTransform(translationX: 0, y: 8)
        }, completion: { _ in
            statusContainer.transform = .identity
            statusContainer.isHidden = true
        })
    }
    
    private func clearInstallStatusLines() {
        installStatusEntries.removeAll()
        installStatusTextView?.attributedText = nil
        installStatusTextView?.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
    }
    
    private func pushInstallStatus(_ text: String) {
        guard !text.isEmpty else { return }
        ensureInstallStatusContainer()
        guard let statusTextView = installStatusTextView else { return }

        installStatusEntries.append(text)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.lineBreakMode = .byTruncatingTail
        
        let attributedText = NSMutableAttributedString()
        for (index, entry) in installStatusEntries.enumerated() {
            if index > 0 {
                attributedText.append(NSAttributedString(string: "\n"))
            }
            let offsetFromEnd = installStatusEntries.count - index
            let alpha: CGFloat
            switch offsetFromEnd {
            case 1:
                alpha = 1.0
            case 2:
                alpha = 0.8
            case 3:
                alpha = 0.65
            default:
                alpha = 0.45
            }
            attributedText.append(NSAttributedString(
                string: entry,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.sileoLabel.withAlphaComponent(alpha),
                    .paragraphStyle: paragraphStyle
                ]
            ))
        }
        statusTextView.attributedText = attributedText
        scrollTextViewToBottom(statusTextView, animated: false)
    }
    
    private func scrollTextViewToBottom(_ textView: UITextView, animated: Bool, retryIfNeeded: Bool = true) {
        textView.layoutIfNeeded()
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let contentHeight = textView.contentSize.height
        let visibleHeight = textView.bounds.height - textView.adjustedContentInset.top - textView.adjustedContentInset.bottom
        guard visibleHeight > 0 else {
            guard retryIfNeeded else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollTextViewToBottom(textView, animated: false, retryIfNeeded: false)
            }
            return
        }
        let offsetY = max(-textView.adjustedContentInset.top, contentHeight - visibleHeight - textView.adjustedContentInset.top)
        textView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: animated)
        
        guard retryIfNeeded else { return }
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.scrollTextViewToBottom(textView, animated: false, retryIfNeeded: false)
        }
    }
    
    public func loadData(_ main: @escaping () -> Void) {
        if Thread.isMainThread {
            fatalError("Wtf are you doing")
        }
        if !isInstalling {
            let manager = DownloadManager.shared
            let upgrades = manager.upgrades.raw.sorted(by: { $0.package.name?.lowercased() ?? "" < $1.package.name?.lowercased() ?? "" })
            let installations = manager.installations.raw.sorted(by: { $0.package.name?.lowercased() ?? "" < $1.package.name?.lowercased() ?? "" })
            let uninstallations = manager.uninstallations.raw.sorted(by: { $0.package.name?.lowercased() ?? "" < $1.package.name?.lowercased() ?? "" })
            let installdeps = manager.installdeps.raw.sorted(by: { $0.package.name?.lowercased() ?? "" < $1.package.name?.lowercased() ?? "" })
            let uninstalldeps = manager.uninstalldeps.raw.sorted(by: { $0.package.name?.lowercased() ?? "" < $1.package.name?.lowercased() ?? "" })
            let errors = manager.errors.raw
            DispatchQueue.main.async { [self] in
                self.upgrades = upgrades
                self.installations = installations
                self.uninstallations = uninstallations
                self.installdeps = installdeps
                self.uninstalldeps = uninstalldeps
                self.errors = ContiguousArray<APTBrokenPackage>(errors)
                main()
            }
            return
        }
        DispatchQueue.main.async { main() }
    }
    
    public func reloadData() {
        DownloadManager.aptQueue.async { [self] in
            self.loadData() {
                self.tableView?.reloadData()
                self.reloadControlsOnly()
            }
            if isDownloading {
                DownloadManager.shared.startMoreDownloads()
            }
        }
    }

    public func reloadControlsOnly() {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.reloadControlsOnly()
            }
            return
        }
        cancelDownload?.isHidden = !isDownloading
        if isFinishedInstalling {
            cancelButton?.isHidden = true
            confirmButton?.isHidden = true
            showDetailsButton?.isHidden = false
            completeButton?.isHidden = false
            completeLaterButton?.isHidden = false
            if completeLaterButton?.alpha == 0 {
                doneToTop?.constant = 0
                laterHeight?.constant = 0
                FRUIView.animate(withDuration: 0.25) {
                    self.footerViewHeight?.constant = 125
                    self.footerView?.alpha = 1
                }
            } else {
                doneToTop?.constant = 15
                laterHeight?.constant = 50
                FRUIView.animate(withDuration: 0.25) {
                    self.footerViewHeight?.constant = 190
                    self.footerView?.alpha = 1
                }
            }
            return
        } else {
            cancelButton?.isHidden = false
            confirmButton?.isHidden = false
            showDetailsButton?.isHidden = true
            completeButton?.isHidden = true
            completeLaterButton?.isHidden = true
        }
        let manager = DownloadManager.shared
        if manager.operationCount() > 0 && !manager.queueStarted && manager.errors.isEmpty {
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 128
                self.footerView?.alpha = 1
            }
        } else if isDownloading {
            cancelButton?.isHidden = true
            confirmButton?.isHidden = true
            showDetailsButton?.isHidden = true
            completeButton?.isHidden = true
            completeLaterButton?.isHidden = true
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 90
                self.footerView?.alpha = 1
            }
        } else {
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 0
                self.footerView?.alpha = 0
            }
        }
        if manager.operationCount() > 0 && manager.verifyComplete() && manager.queueStarted && manager.errors.isEmpty {
            manager.lockedForInstallation = true
            isDownloading = false
            cancelDownload?.isHidden = true
            FRUIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
                self.footerViewHeight?.constant = 0
                self.footerView?.alpha = 0
            }, completion: { _ in
                self.transferToInstall()
                TabBarController.singleton?.restoreQueueCollapsedInteractionStyle()
            })
        }
        if manager.errors.isEmpty {
            self.confirmButton?.isEnabled = true
            self.confirmButton?.alpha = 1
        } else {
            self.confirmButton?.isEnabled = false
            self.confirmButton?.alpha = 0.5
        }
    }
    
    public func reloadDownload(package: Package?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [self] in
                self.reloadDownload(package: package)
            }
            return
        }
        guard let package = package else {
            return
        }
        let dlPackage = DownloadPackage(package: package)
        var rawIndexPath: IndexPath?
        let installsAndDeps = installations + installdeps
        if installsAndDeps.contains(dlPackage) {
            rawIndexPath = IndexPath(row: installsAndDeps.firstIndex(of: dlPackage) ?? -1, section: 0)
        } else if upgrades.contains(dlPackage) {
            rawIndexPath = IndexPath(row: upgrades.firstIndex(of: dlPackage) ?? -1, section: 2)
        }
        guard let indexPath = rawIndexPath else {
            return
        }
        guard let cell = self.tableView?.cellForRow(at: indexPath) as? DownloadsTableViewCell else {
            return
        }
        cell.download = DownloadManager.shared.download(package: package.packageID)
        cell.layoutSubviews()
    }
    
    @IBAction public func cancelDownload(_ sender: Any?) {
        isInstalling = false
        isDownloading = false
        isFinishedInstalling = false
        returnButtonAction = .back
        refreshSileo = false
        hasErrored = false
        setInstallStatusVisible(false)
        clearInstallStatusLines()
        tableView?.setEditing(true, animated: true)
        self.actions.removeAll()
        
        DownloadManager.shared.cancelDownloads()
        DownloadManager.shared.queueStarted = false
        if sender != nil {
            DownloadManager.shared.reloadData(recheckPackages: false)
        }
    }
    
    @IBAction func cancelQueued(_ sender: Any?) {
        isInstalling = false
        isDownloading = false
        isFinishedInstalling = false
        returnButtonAction = .back
        refreshSileo = false
        hasErrored = false
        setInstallStatusVisible(false)
        clearInstallStatusLines()
        tableView?.setEditing(true, animated: true)
        self.actions.removeAll()
        
        DownloadManager.shared.queueStarted = false
        DownloadManager.aptQueue.async {
            DownloadManager.shared.removeAllItems()
            DownloadManager.shared.reloadData(recheckPackages: true)
        }

        TabBarController.singleton?.dismissPopupController(completion: { [self] in
            tableView?.setEditing(true, animated: true)
        })
        TabBarController.singleton?.updatePopup(bypass: true)
    }
    
    @IBAction func confirmQueued(_ sender: Any?) {
        if sender != nil {
            let actions = uninstallations + uninstalldeps
            let essentialPackages = actions.map { $0.package }.filter { DownloadManager.shared.isEssential($0) }
            if essentialPackages.isEmpty {
                return confirmQueued(nil)
            }
            let formatPackages = essentialPackages.map { "\n\($0.name ?? $0.packageID)" }.joined()
            let message = String(format: String(localizationKey: "Essential_Warning"), formatPackages)
            let alert = UIAlertController(title: String(localizationKey: "Warning"),
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .default, handler: { _ in
                alert.dismiss(animated: true)
            }))
            alert.addAction(UIAlertAction(title: String(localizationKey: "Dangerous_Repo.Last_Chance.Continue"), style: .destructive, handler: { _ in
                self.confirmQueued(nil)
            }))
            self.present(alert, animated: true, completion: nil)
            return
        }
        isDownloading = true
    
        DownloadManager.shared.startMoreDownloads()
        DownloadManager.shared.reloadData(recheckPackages: false)
        DownloadManager.shared.queueStarted = true
    }
    
    override func accessibilityPerformEscape() -> Bool {
        TabBarController.singleton?.dismissPopupController()
        return true
    }
    
    public func transferToInstall() {
        if isInstalling {
            return
        }
        isInstalling = true
        TabBarController.singleton?.restoreQueueCollapsedInteractionStyle()
        var earlyBreak = false
        if UIApplication.shared.applicationState == .background || UIApplication.shared.applicationState == .inactive,
           let completion = backgroundCallback {
            earlyBreak = true
            completion()
        }
        tableView?.setEditing(false, animated: true)
        
        for cell in tableView?.visibleCells as? [DownloadsTableViewCell] ?? [] {
            cell.setEditing(false, animated: true)
        }
        
        detailsAttributedString = NSMutableAttributedString(string: "")
        clearInstallStatusLines()
        setInstallStatusVisible(true)
        let installs = installations + upgrades + installdeps
        if UserDefaults.standard.bool(forKey: "CanisterIngest", fallback: false) {
            CanisterResolver.shared.ingest(packages: installs.map { $0.package })
        }
        let removals = uninstallations + uninstalldeps
        self.actions += installs.map { InstallOperation(package: $0.package, operation: .install) }
        self.actions += removals.map { InstallOperation(package: $0.package, operation: .removal) }
        
        for cell in tableView?.visibleCells as? [DownloadsTableViewCell] ?? [] {
            guard let action = actions.first(where: { $0.package.packageID == cell.package?.package.packageID }) else {
                continue
            }
            cell.package = nil
            cell.download = nil
            cell.operation = action
            cell.setEditing(false, animated: true)
        }
        if UserDefaults.standard.bool(forKey: "AlwaysShowLog", fallback: false) {
            showDetails(nil)
        }
        if !earlyBreak {
            startInstall()
        }
    }
    
    public func statusWork(package: String, status: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.statusWork(package: package, status: status)
            }
            return
        }
        if let action = actions.first(where: { $0.package.packageID == package }) {
            action.progressCounter += 1
            action.status = status
            action.cell?.operation = action
        }
        pushInstallStatus(status)
    }
    
    @IBAction func completeButtonTapped(_ sender: Any?) {
        if (returnButtonAction == .back || returnButtonAction == .uicache) && !refreshSileo {
            completeLaterButtonTapped(sender)
            return
        }
        
        guard let window = UIApplication.shared.windows.first else { return completeLaterButtonTapped(sender) }
        isFired = true
        setNeedsStatusBarAppearanceUpdate()
        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) {
            window.alpha = 0
            window.transform = .init(scaleX: 0.9, y: 0.9)
        }

        // When the animation has finished, fire the dumb respring code
        animator.addCompletion { _ in
            switch self.returnButtonAction {
            case .back, .uicache:
                spawn(command: CommandPath.uicache, args: ["uicache", "-p", "\(Bundle.main.bundlePath)"]); exit(0)
            case .reopen:
                exit(0)
            case .restart, .reload:
                if self.refreshSileo {
                    spawn(command: CommandPath.uicache, args: ["uicache", "-p", "\(Bundle.main.bundlePath)"])
                }
                spawn(command: "\(CommandPath.prefix)/usr/bin/sbreload", args: ["sbreload"])
                while true {
                   window.snapshotView(afterScreenUpdates: false)
                }
            case .reboot:
                spawnAsRoot(args: ["\(CommandPath.prefix)/usr/bin/sync"])
                spawnAsRoot(args: ["\(CommandPath.prefix)/usr/bin/ldrestart"])
            case .usreboot:
                spawnAsRoot(args: ["\(CommandPath.prefix)/usr/bin/sync"])
                spawnAsRoot(args: ["\(CommandPath.prefix)/usr/bin/launchctl", "reboot", "userspace"])
            }
        }
        // Fire the animation
        animator.startAnimation()
    }
    
    @IBAction func completeLaterButtonTapped(_ sender: Any?) {
        isInstalling = false
        isFinishedInstalling = false
        returnButtonAction = .back
        refreshSileo = false
        hasErrored = false
        setInstallStatusVisible(false)
        clearInstallStatusLines()
        tableView?.setEditing(true, animated: true)
        actions.removeAll()

        TabBarController.singleton?.restoreQueueCollapsedInteractionStyle()
        DownloadManager.shared.lockedForInstallation = false
        DownloadManager.shared.queueStarted = false
        DownloadManager.aptQueue.async {
            DownloadManager.shared.removeAllItems()
            DownloadManager.shared.reloadData(recheckPackages: true)
        }
        TabBarController.singleton?.dismissPopupController()
        TabBarController.singleton?.updatePopup(bypass: true)
    }
    
    func transform(attributedString: NSMutableAttributedString) -> NSMutableAttributedString {
        let font = UIFont(name: "Menlo-Regular", size: 12) ?? UIFont.systemFont(ofSize: 12)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 4
        
        attributedString.addAttributes([
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ], range: NSRange(location: 0, length: attributedString.length))
        return attributedString
    }
    
    private func startInstall() {
        
        func shouldShow(_ finish: APTWrapper.FINISH) -> Bool {
            finish == .restart || finish == .reopen || finish == .reload || finish == .reboot
        }
        
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        // swiftlint:disable:next line_length
        let testAPTStatus = "pmstatus:dpkg-exec:0.0000:Running dpkg\npmstatus:com.daveapps.quitall:0.0000:Installing com.daveapps.quitall (iphoneos-arm)\npmstatus:com.daveapps.quitall:9.0909:Preparing com.daveapps.quitall (iphoneos-arm)\npmstatus:com.daveapps.quitall:18.1818:Unpacking com.daveapps.quitall (iphoneos-arm)\npmstatus:com.daveapps.quitall:27.2727:Preparing to configure com.daveapps.quitall (iphoneos-arm)\npmstatus:dpkg-exec:27.2727:Running dpkg\npmstatus:com.daveapps.quitall:27.2727:Configuring com.daveapps.quitall (iphoneos-arm)\npmstatus:com.daveapps.quitall:36.3636:Configuring com.daveapps.quitall (iphoneos-arm)\npmstatus:com.daveapps.quitall:45.4545:Installed com.daveapps.quitall (iphoneos-arm)\npmstatus:dpkg-exec:45.4545:Running dpkg\npmstatus:com.amywhile.macspoof:45.4545:Installing com.amywhile.macspoof (iphoneos-arm)\npmstatus:com.amywhile.macspoof:54.5455:Preparing com.amywhile.macspoof (iphoneos-arm)\npmstatus:com.amywhile.macspoof:63.6364:Unpacking com.amywhile.macspoof (iphoneos-arm)\npmstatus:com.amywhile.macspoof:72.7273:Preparing to configure com.amywhile.macspoof (iphoneos-arm)\npmstatus:dpkg-exec:72.7273:Running dpkg\npmstatus:com.amywhile.macspoof:72.7273:Configuring com.amywhile.macspoof (iphoneos-arm)\npmstatus:com.amywhile.macspoof:81.8182:Configuring com.amywhile.macspoof (iphoneos-arm)\npmstatus:com.amywhile.macspoof:90.9091:Installed com.amywhile.macspoof (iphoneos-arm)"
        DispatchQueue.global(qos: .default).async {
            let aptStatuses = testAPTStatus.components(separatedBy: "\n")
            for status in aptStatuses {
                let (statusValid, _, readableStatus, package) = APTWrapper.installProgress(aptStatus: status)
                if statusValid {
                    self.statusWork(package: package, status: readableStatus)
                }
                usleep(useconds_t(50 * USEC_PER_SEC/1000))
            }
            for file in DownloadManager.shared.cachedFiles {
                deleteFileAsRoot(file)
            }
            PackageListManager.shared.reloadInstalled()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PackageListManager.stateChange, object: nil)
                NotificationCenter.default.post(name: PackageListManager.installChange, object: nil)
                
                let rawUpdates = PackageListManager.shared.availableUpdates()
                let updatesNotIgnored = rawUpdates.filter({ $0.1?.wantInfo != .hold })
                UIApplication.shared.applicationIconBadgeNumber = updatesNotIgnored.count
                
                _ = self.actions.map { $0.progressCounter = 7 }
                for cell in (self.tableView?.visibleCells as? [DownloadsTableViewCell] ?? []) {
                    let operation = cell.operation
                    cell.operation = operation
                }
                self.returnButtonAction = .back
                self.updateCompleteButton()
                self.completeButton?.alpha = 1
                self.showDetailsButton?.isHidden = false
                self.completeLaterButton?.alpha = shouldShow(.back) ? 1 : 0
                self.refreshSileo = false
                
                self.isFinishedInstalling = true
                self.reloadControlsOnly()
                
                if !(TabBarController.singleton?.isQueuePresentationVisible ?? false) {
                    self.completeButtonTapped(nil)
                }
                NotificationCenter.default.post(name: NSNotification.Name("Sileo.CompleteInstall"), object: nil)
            }
        }
        #else
        
        if let detailsAttributedString = self.detailsAttributedString {
            detailsTextView?.attributedText = self.transform(attributedString: detailsAttributedString)
        }

        APTWrapper.performOperations(installs: installations + upgrades, removals: uninstallations, installDeps: installdeps, progressCallback: { _, statusValid, statusReadable, package in
            if statusValid {
                self.statusWork(package: package, status: statusReadable)
            }
        }, outputCallback: { output, pipe in
            var textColor = Dusk.foregroundColor
            if pipe == STDERR_FILENO {
                textColor = Dusk.errorColor
                self.hasErrored = true
            }
            if pipe == APTWrapper.debugFD {
                textColor = Dusk.debugColor
            }
            
            if output.prefix(2) == "W:" || output.contains("dpkg: warning") {
                textColor = Dusk.warningColor
            }
            
            let substring = NSMutableAttributedString(string: output, attributes: [NSAttributedString.Key.foregroundColor: textColor])
            DispatchQueue.main.async {
                self.detailsAttributedString?.append(substring)
                
                guard let detailsAttributedString = self.detailsAttributedString else {
                    return
                }
                self.detailsTextView?.attributedText = self.transform(attributedString: detailsAttributedString)
                
                if let detailsTextView = self.detailsTextView {
                    self.scrollTextViewToBottom(detailsTextView, animated: false)
                }
            }
        }, completionCallback: { _, finish, refresh in
            PackageListManager.shared.reloadInstalled()
            DispatchQueue.main.async {
                
                NotificationCenter.default.post(name: PackageListManager.stateChange, object: nil)
                NotificationCenter.default.post(name: PackageListManager.installChange, object: nil)
                let rawUpdates = PackageListManager.shared.availableUpdates()
                let updatesNotIgnored = rawUpdates.filter({ $0.1?.wantInfo != .hold })
                UIApplication.shared.applicationIconBadgeNumber = updatesNotIgnored.count
                
                _ = self.actions.map { $0.progressCounter = 7 }
                for cell in (self.tableView?.visibleCells as? [DownloadsTableViewCell] ?? []) {
                    let operation = cell.operation
                    cell.operation = operation
                }
                self.returnButtonAction = finish
                self.refreshSileo = refresh
                self.updateCompleteButton()
                self.completeButton?.alpha = 1
                self.showDetailsButton?.isHidden = false
                self.completeLaterButton?.alpha = shouldShow(finish) ? 1 : 0
                
                self.isFinishedInstalling = true
                self.reloadControlsOnly()
                
                if (UserDefaults.standard.bool(forKey: "AutoComplete") && !self.hasErrored) || !(TabBarController.singleton?.isQueuePresentationVisible ?? false) {
                    self.completeButtonTapped(nil)
                }
                NotificationCenter.default.post(name: NSNotification.Name("Sileo.CompleteInstall"), object: nil)
            }
        })
        #endif
    }
        
    func updateCompleteButton() {
        switch returnButtonAction {
        case .back:
            if refreshSileo {
                completeButton?.setTitle(String(localizationKey: "After_Install_Relaunch"), for: .normal)
                completeLaterButton?.setTitle(String(localizationKey: "After_Install_Relaunch_Later"), for: .normal)
                break }
            completeButton?.setTitle(String(localizationKey: "Done"), for: .normal)
        case .reopen:
            completeButton?.setTitle(String(localizationKey: "After_Install_Relaunch"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Relaunch_Later"), for: .normal)
        case .restart, .reload:
            completeButton?.setTitle(String(localizationKey: "After_Install_Respring"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Respring_Later"), for: .normal)
        case .reboot:
            completeButton?.setTitle(String(localizationKey: "After_Install_Reboot"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Reboot_Later"), for: .normal)
        case .usreboot:
            completeButton?.setTitle(String(localizationKey: "After_Install_Reboot"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Reboot_Later"), for: .normal)
        case .uicache:
            if refreshSileo {
                completeButton?.setTitle(String(localizationKey: "After_Install_Relaunch"), for: .normal)
                completeLaterButton?.setTitle(String(localizationKey: "After_Install_Relaunch_Later"), for: .normal)
            } else {
                completeButton?.setTitle(String(localizationKey: "Done"), for: .normal)
            }
        }
    }
    
    @IBAction func showDetails(_ sender: Any?) {
        guard let detailsView = self.detailsView else {
            return
        }
        TabBarController.singleton?.restoreQueueCollapsedInteractionStyle()
        detailsView.alpha = 0
        detailsView.transform = CGAffineTransform(translationX: 0, y: 10)
        detailsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        detailsView.frame = supportsFloatingSheetChrome ? floatingDetailsFrame() : self.view.bounds
        if supportsFloatingSheetChrome {
            detailsView.layer.cornerRadius = floatingCornerRadius
            if #available(iOS 13.0, *) {
                detailsView.layer.cornerCurve = .continuous
            }
            detailsView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            detailsView.layer.masksToBounds = true
        } else {
            detailsView.layer.cornerRadius = 0
        }
        
        self.view.addSubview(detailsView)
        
        self.view.bringSubviewToFront(detailsView)
        detailsView.layoutIfNeeded()
        if let detailsTextView = self.detailsTextView {
            self.scrollTextViewToBottom(detailsTextView, animated: false)
        }
        FRUIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
            self.detailsView?.alpha = 1
            self.detailsView?.transform = .identity
            
            self.statusBarStyle = .lightContent
            self.setNeedsStatusBarAppearanceUpdate()
        })
    }
    
    @IBAction func hideDetails(_ sender: Any?) {
        FRUIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
            self.detailsView?.alpha = 0
            self.detailsView?.transform = CGAffineTransform(translationX: 0, y: 10)
            
            self.statusBarStyle = .default
            self.setNeedsStatusBarAppearanceUpdate()
        }, completion: { _ in
            self.detailsView?.transform = .identity
            self.detailsView?.removeFromSuperview()
        })
    }

}

extension DownloadsTableViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        6
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return installations.count + installdeps.count
        case 1:
            return uninstallations.count + uninstalldeps.count
        case 2:
            return upgrades.count
        case 3:
            return errors.count
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView.numberOfRows(inSection: section) == 0 {
            return nil
        }
        switch section {
        case 0:
            return String(localizationKey: "Queued_Install_Heading")
        case 1:
            return String(localizationKey: "Queued_Uninstall_Heading")
        case 2:
            return String(localizationKey: "Queued_Update_Heading")
        case 3:
            return String(localizationKey: "Download_Errors_Heading")
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if (self.tableView?.numberOfRows(inSection: section) ?? 0) > 0 {
            let headerView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 320, height: 36)))
            headerView.backgroundColor = .sileoBackgroundColor
            headerView.isOpaque = true
            headerView.clipsToBounds = true
            
            if let text = self.tableView(tableView, titleForHeaderInSection: section) {
                let titleView = SileoLabelView(frame: CGRect(x: 16, y: 0, width: 320, height: 28))
                titleView.font = UIFont.systemFont(ofSize: 22, weight: .bold)
                titleView.text = text
                titleView.autoresizingMask = .flexibleWidth
                headerView.addSubview(titleView)
                
                let separatorView = SileoSeparatorView(frame: CGRect(x: 16, y: 35, width: 304, height: 1))
                separatorView.autoresizingMask = .flexibleWidth
                headerView.addSubview(separatorView)
            }
            return headerView
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.tableView(tableView, numberOfRowsInSection: section) > 0 {
            return 36
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView() // do not show extraneous tableview separators
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        8
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        58
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "DownloadsTableViewCell"
        // swiftlint:disable force_cast
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! DownloadsTableViewCell
        if indexPath.section == 3 {
            // Error listing
            let error = errors[indexPath.row]
            let allPackages = upgrades + installations + installdeps + uninstallations + uninstalldeps
            if let package = allPackages.first(where: { $0.package.package == error.packageID }) {
                cell.package = package
            } else {
                let package = Package(package: error.packageID, version: "-1")
                cell.package = DownloadPackage(package: package)
            }
            cell.title = error.packageID
            var description = ""
            for (index, conflict) in error.conflictingPackages.enumerated() {
                description += "\(conflict.conflict.rawValue) \(conflict.package)\(index == error.conflictingPackages.count - 1 ? "" : ", ")"
            }
            cell.errorDescription = description
            cell.download = nil
        } else {
            // Normal operation listing
            var array: [DownloadPackage] = []
            switch indexPath.section {
            case 0:
                array = installations + installdeps
            case 1:
                array = uninstallations + uninstalldeps
            case 2:
                array = upgrades
            default:
                break
            }
            
            if isInstalling {
                guard let action = actions.first(where: { $0.package.packageID == array[indexPath.row].package.packageID }) else {
                    return cell
                }
                cell.internalPackage = action.package
                cell.operation = action
                action.cell = cell
            } else {
                cell.package = array[indexPath.row]
                cell.shouldHaveDownload = indexPath.section == 0 || indexPath.section == 2
                cell.errorDescription = nil
                cell.download = DownloadManager.shared.download(package: cell.package?.package.package ?? "")
            }
        }
        return cell
    }
}

extension DownloadsTableViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 3 || isInstalling {
            return false
        }
        var array: [DownloadPackage] = []
        switch indexPath.section {
        case 0:
            array = installations
        case 1:
            array = uninstallations
        case 2:
            array = upgrades
        default:
            break
        }
        if indexPath.row >= array.count {
            return false
        }
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            var queue: DownloadManagerQueue = .none
            var array: [DownloadPackage] = []
            switch indexPath.section {
            case 0:
                array = installations
                queue = .installations
                installations.remove(at: indexPath.row)
            case 1:
                array = uninstallations
                queue = .uninstallations
                uninstallations.remove(at: indexPath.row)
            case 2:
                array = upgrades
                queue = .upgrades
                upgrades.remove(at: indexPath.row)
            default:
                break
            }
            if indexPath.section == 3 || indexPath.row >= array.count {
                fatalError("Invalid section/row (not editable)")
            }
            
            let downloadManager = DownloadManager.shared
            downloadManager.remove(downloadPackage: array[indexPath.row], queue: queue)
            tableView.deleteRows(at: [indexPath], with: .fade)
            downloadManager.reloadData(recheckPackages: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
