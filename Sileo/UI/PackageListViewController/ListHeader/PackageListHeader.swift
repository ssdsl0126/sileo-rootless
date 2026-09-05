//
//  PackageListHeader.swift
//  Sileo
//
//  Created by CoolStar on 7/9/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

class PackageListHeader: UICollectionReusableView {
    @IBOutlet weak var label: UILabel?
    @IBOutlet weak var toolbar: UIToolbar?
    @IBOutlet weak var upgradeButton: UIButton?
    @IBOutlet weak var sortIcon: UIImageView?
    @IBOutlet weak var sortHeader: UILabel?
    @IBOutlet weak var separatorView: UIView?
    @IBOutlet weak var sortContainer: UIControl?

    private var usesPinnedGlassSurface: Bool {
        sortContainer != nil || upgradeButton != nil
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        toolbar?._hidesShadow = true
        toolbar?.tag = WHITE_BLUR_TAG

        if #available(iOS 26.0, *) {
            // iOS 26 的分组标题元素分别配置胶囊，新闻日期标题只保留日期胶囊。
            clipsToBounds = false
            backgroundColor = .clear
            isOpaque = false
            toolbar?.removeFromSuperview()
            toolbar?.isHidden = true
            toolbar?.tag = 0
            toolbar?.isTranslucent = false
            toolbar?.setBackgroundImage(nil, forToolbarPosition: .any, barMetrics: .default)
            toolbar?.setShadowImage(nil, forToolbarPosition: .any)
            toolbar?.backgroundColor = .sileoBackgroundColor
            for subview in subviews {
                if subview is SileoSeparatorView || String(describing: type(of: subview)).contains("Separator") {
                    subview.removeFromSuperview()
                }
            }
        }
        
        sortIcon?.image = UIImage(named: "SortChevron")?.withRenderingMode(.alwaysTemplate)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        updateSileoColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #available(iOS 26.0, *) {
            clipsToBounds = false
            hideLegacySeparatorViews()
            if usesPinnedGlassSurface {
                centerLegacyElementsForCompactGlassHeader()
            } else {
                layoutNewsDateHeaderCapsule()
            }
            refreshPinnedGlassContent()
            // iOS 26 由胶囊玻璃自然过渡到首行，不再绘制旧版硬分隔线。
            hideLegacySeparatorViews()
        }
    }

    private func layoutNewsDateHeaderCapsule() {
        guard let label, let container = label.superview else {
            return
        }
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75

        let maxContainerWidth = max(44, bounds.width - 30)
        let measuredTextWidth = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 24)).width
        let targetContainerWidth = min(maxContainerWidth, max(44, ceil(measuredTextWidth) + 20))

        var containerFrame = container.frame
        containerFrame.origin.x = 15
        containerFrame.origin.y = (bounds.height - 24) / 2
        containerFrame.size.width = targetContainerWidth
        containerFrame.size.height = 24
        container.frame = containerFrame
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true

        label.frame = CGRect(x: 10, y: 0, width: max(0, targetContainerWidth - 20), height: 24)
    }

    private func centerLegacyElementsForCompactGlassHeader() {
        let elements: [UIView?] = [label, sortContainer, upgradeButton]
        for element in elements.compactMap({ $0 }) {
            var frame = element.frame
            frame.origin.y = (bounds.height - frame.height) / 2
            element.frame = frame
        }
    }

    private func hideLegacySeparatorViews() {
        guard #available(iOS 26.0, *) else {
            return
        }

        separatorView?.isHidden = true
        separatorView?.alpha = 0
        for subview in subviews {
            if subview is SileoSeparatorView || subview === separatorView ||
                String(describing: type(of: subview)).contains("Separator") ||
                (subview !== label && subview !== sortContainer && subview !== upgradeButton &&
                 subview.bounds.height <= 3) {
                subview.removeFromSuperview()
            }
        }
    }

    func refreshPinnedGlassContent() {
        guard #available(iOS 26.0, *), usesPinnedGlassSurface else {
            return
        }

        // 固定标题不显示旧版横向分隔线，避免复用后被数据源重新打开。
        hideLegacySeparatorViews()

        if let label {
                    SileoGlass.configurePinnedHeaderElementSurface(for: label,
                                                                    in: self,
                                                                    identifier: "title",
                                                                    contentColor: .sileoLabel)
        }
        if let sortContainer {
            let sortWidth = (sortHeader?.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                               height: sortHeader?.bounds.height ?? 0)).width ?? 0) +
                (sortIcon?.bounds.width ?? 16) + 3
            SileoGlass.configurePinnedHeaderElementSurface(for: sortContainer,
                                                            in: self,
                                                            identifier: "sort",
                                                            contentWidth: sortWidth,
                                                            alignToTrailing: true,
                                                            contentText: sortHeader?.text,
                                                            contentFont: sortHeader?.font,
                                                            contentColor: .tintColor,
                                                            contentImage: sortIcon?.image,
                                                            contentImageTintColor: .tintColor)
            sortHeader?.textColor = .clear
            sortIcon?.isHidden = true
        }
        if let upgradeButton {
            SileoGlass.configurePinnedHeaderElementSurface(for: upgradeButton,
                                                            in: self,
                                                            identifier: "action",
                                                            alignToTrailing: true,
                                                            contentText: upgradeButton.title(for: .normal),
                                                            contentFont: upgradeButton.titleLabel?.font,
                                                            contentColor: .tintColor)
        }
    }
    
    @objc func updateSileoColors() {
        label?.textColor = .sileoLabel
        sortIcon?.tintColor = .tintColor
        sortHeader?.textColor = .tintColor
        if #available(iOS 26.0, *) {
            backgroundColor = .clear
            isOpaque = false
            setNeedsLayout()
        }
    }
    
    public var actionText: String? {
        didSet {
            if let actionText = actionText {
                upgradeButton?.setTitle(actionText, for: .normal)
                upgradeButton?.isHidden = false
            } else {
                upgradeButton?.isHidden = true
            }
            setNeedsLayout()
        }
    }
}
