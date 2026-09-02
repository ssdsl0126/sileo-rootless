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
    @IBOutlet weak var separatorView: UIImageView?
    @IBOutlet weak var sortContainer: UIControl?

    private var usesPinnedGlassSurface: Bool {
        sortContainer != nil || upgradeButton != nil
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        toolbar?._hidesShadow = true
        toolbar?.tag = WHITE_BLUR_TAG

        if #available(iOS 26.0, *) {
            if usesPinnedGlassSurface {
                // 分组标题使用玻璃表面，遮住后面的首行并与导航栏连续。
                SileoGlass.configurePinnedHeaderSurface(self)
            } else {
                // 新闻日期标题只保留日期胶囊，不铺满整行玻璃。
                backgroundColor = .clear
                isOpaque = false
            }
            toolbar?.isHidden = true
            toolbar?.tag = 0
            toolbar?.isTranslucent = false
            toolbar?.setBackgroundImage(nil, forToolbarPosition: .any, barMetrics: .default)
            toolbar?.setShadowImage(nil, forToolbarPosition: .any)
            toolbar?.backgroundColor = .sileoBackgroundColor
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
            // iOS 26 由玻璃表面自然过渡到首行，不再绘制旧版硬分隔线。
            separatorView?.isHidden = true
        }
    }
    
    @objc func updateSileoColors() {
        label?.textColor = .sileoLabel
        sortIcon?.tintColor = .tintColor
        sortHeader?.textColor = .tintColor
        if #available(iOS 26.0, *), usesPinnedGlassSurface {
            SileoGlass.configurePinnedHeaderSurface(self)
        } else if #available(iOS 26.0, *) {
            backgroundColor = .clear
            isOpaque = false
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
        }
    }
}
