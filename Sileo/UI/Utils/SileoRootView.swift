//
//  SileoRootView.swift
//  Sileo
//
//  Created by CoolStar on 9/8/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import UIKit

class SileoRootView: UIView {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        self.backgroundColor = .sileoBackgroundColor
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        self.backgroundColor = .sileoBackgroundColor
    }
    
    @objc func updateSileoColors() {
        self.backgroundColor = .sileoBackgroundColor
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateSileoColors()
    }
}

/// 为 iOS 26 提供原生 Liquid Glass，同时为 iOS 15–18 保留材质回退。
enum SileoGlass {
    private static let pinnedHeaderSurfaceIdentifier = "Sileo.iOS26.PinnedHeaderSurface"

    static var isSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    static func effect(interactive: Bool = false,
                       tintColor: UIColor? = nil,
                       fallbackStyle: UIBlurEffect.Style = .systemMaterial) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = interactive
            glassEffect.tintColor = tintColor
            return glassEffect
        }

        if #available(iOS 13.0, *) {
            return UIBlurEffect(style: fallbackStyle)
        }
        return UIBlurEffect(style: .light)
    }

    static func update(_ view: UIVisualEffectView,
                       interactive: Bool = false,
                       tintColor: UIColor? = nil,
                       fallbackStyle: UIBlurEffect.Style = .systemMaterial) {
        view.effect = effect(interactive: interactive,
                             tintColor: tintColor,
                             fallbackStyle: fallbackStyle)
    }

    /// 将主要操作按钮切换到系统 Liquid Glass 配置，旧系统保持原有样式。
    static func update(button: UIButton,
                       isProminent: Bool,
                       tintColor: UIColor,
                       title: String? = nil,
                       contentInsets: NSDirectionalEdgeInsets = .init(top: 6, leading: 12, bottom: 6, trailing: 12)) {
        guard #available(iOS 26.0, *) else {
            return
        }

        // 首页和插件详情 CTA 使用主题色玻璃底，文字固定为白色。
        // isProminent 仍保留在接口中，旧系统继续由 PackageButton 使用原有实色逻辑。
        var configuration = UIButton.Configuration.prominentGlass()
        let preservedTitle = title ?? button.title(for: .normal)
        if let previousConfiguration = button.configuration {
            // 切换高亮或 prominent 状态时保留原有标题和内容，避免按钮变成空白胶囊。
            if let preservedTitle, !preservedTitle.isEmpty {
                configuration.title = preservedTitle
                configuration.attributedTitle = nil
            } else if let attributedTitle = previousConfiguration.attributedTitle {
                configuration.attributedTitle = attributedTitle
            } else {
                configuration.title = previousConfiguration.title
            }
            if let attributedSubtitle = previousConfiguration.attributedSubtitle {
                configuration.attributedSubtitle = attributedSubtitle
            } else {
                configuration.subtitle = previousConfiguration.subtitle
            }
            configuration.image = previousConfiguration.image
            configuration.imageColorTransformer = previousConfiguration.imageColorTransformer
            configuration.preferredSymbolConfigurationForImage = previousConfiguration.preferredSymbolConfigurationForImage
            configuration.showsActivityIndicator = previousConfiguration.showsActivityIndicator
        } else if let preservedTitle, !preservedTitle.isEmpty {
            configuration.title = preservedTitle
            configuration.attributedTitle = nil
        }
        configuration.cornerStyle = .capsule
        configuration.contentInsets = contentInsets
        configuration.baseBackgroundColor = tintColor
        // 首页 CTA 的文字固定为白色，与导航栏顶部按钮的配色方向相反。
        configuration.baseForegroundColor = .white
        button.configuration = configuration
    }

    /// 为 iOS 26 的导航栏按钮保留系统共享玻璃背景，避免全局 tint 覆盖文字颜色。
    static func configure(barButtonItem: UIBarButtonItem, tintColor: UIColor) {
        guard #available(iOS 26.0, *) else {
            return
        }
        barButtonItem.tintColor = tintColor
        barButtonItem.hidesSharedBackground = false
        barButtonItem.sharesBackground = true
    }

    /// 为 iOS 26 的列表建立连续内容面，避免滚动回弹时露出第二套背景层。
    static func configureScrollSurface(_ scrollView: UIScrollView,
                                       in viewController: UIViewController) {
        guard #available(iOS 26.0, *) else {
            return
        }

        let surfaceColor = UIColor.sileoBackgroundColor
        viewController.view.backgroundColor = surfaceColor
        let usesTopGlassTransition = viewController is NewsViewController ||
            viewController is PackageListViewController ||
            viewController is SourcesViewController
        if usesTopGlassTransition {
            // 这三个列表页需要让系统导航玻璃连续取景。
            scrollView.backgroundColor = .clear
            scrollView.isOpaque = false
        } else {
            // 其它页面保持现有 iOS 26 内容面，避免扩大本次修复范围。
            scrollView.backgroundColor = surfaceColor
            scrollView.isOpaque = true
        }
        // iOS 26 的导航栏与标签栏必须观察同一个滚动视图，保持上下玻璃边界连续。
        viewController.setContentScrollView(scrollView, for: .top)
        viewController.setContentScrollView(scrollView, for: .bottom)
        viewController.navigationController?.setContentScrollView(scrollView, for: .top)
        viewController.navigationController?.setContentScrollView(scrollView, for: .bottom)
    }

    /// 为 iOS 26 的固定分组标题元素添加按内容自适应的玻璃胶囊。
    static func configurePinnedHeaderElementSurface(for element: UIView,
                                                     in headerView: UIView,
                                                     identifier: String,
                                                     contentWidth: CGFloat? = nil,
                                                     alignToTrailing: Bool = false,
                                                     contentText: String? = nil,
                                                     contentFont: UIFont? = nil,
                                                     contentColor: UIColor? = nil,
                                                     contentImage: UIImage? = nil,
                                                     contentImageTintColor: UIColor? = nil) {
        guard #available(iOS 26.0, *) else {
            return
        }

        headerView.backgroundColor = .clear
        headerView.isOpaque = false

        let surfaceView: UIVisualEffectView
        if let existingView = headerView.subviews.first(where: {
            $0.accessibilityIdentifier == "\(pinnedHeaderSurfaceIdentifier).\(identifier)"
        }) as? UIVisualEffectView {
            surfaceView = existingView
        } else {
            let createdView = UIVisualEffectView(effect: nil)
            createdView.accessibilityIdentifier = "\(pinnedHeaderSurfaceIdentifier).\(identifier)"
            createdView.isUserInteractionEnabled = false
            headerView.insertSubview(createdView, at: 0)
            surfaceView = createdView
        }

        let measuredWidth: CGFloat
        if let contentWidth, contentWidth > 0 {
            measuredWidth = contentWidth
        } else if let label = element as? UILabel {
            measuredWidth = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: element.bounds.height)).width
        } else {
            measuredWidth = element.bounds.width
        }

        let horizontalPadding: CGFloat = 14
        let width = max(44, measuredWidth + (horizontalPadding * 2))
        let height: CGFloat = 44
        let elementFrame = element.frame
        let originX = alignToTrailing ? elementFrame.maxX - width : elementFrame.minX
        headerView.clipsToBounds = false
        surfaceView.frame = CGRect(x: originX,
                                   y: elementFrame.midY - (height / 2),
                                   width: min(width, max(0, headerView.bounds.width - originX)),
                                   height: height)
        surfaceView.cornerConfiguration = .capsule()
        surfaceView.backgroundColor = .clear
        let glassEffect = UIGlassEffect(style: .regular)
        // 小胶囊需要比整块内容面更稳定，降低底下图标和进度线的穿透感。
        glassEffect.tintColor = UIColor.sileoBackgroundColor.withAlphaComponent(0.65)
        surfaceView.effect = glassEffect
        surfaceView.isHidden = element.isHidden
        headerView.bringSubviewToFront(surfaceView)

        let titleLabel: UILabel
        if let existingLabel = surfaceView.contentView.subviews.first(where: {
            $0.accessibilityIdentifier == "\(pinnedHeaderSurfaceIdentifier).\(identifier).Title"
        }) as? UILabel {
            titleLabel = existingLabel
        } else {
            let createdLabel = UILabel()
            createdLabel.accessibilityIdentifier = "\(pinnedHeaderSurfaceIdentifier).\(identifier).Title"
            createdLabel.isUserInteractionEnabled = false
            createdLabel.textAlignment = .center
            createdLabel.numberOfLines = 1
            createdLabel.lineBreakMode = .byTruncatingTail
            surfaceView.contentView.addSubview(createdLabel)
            titleLabel = createdLabel
        }

        let resolvedText: String?
        let resolvedFont: UIFont?
        let resolvedColor: UIColor?
        if let label = element as? UILabel {
            resolvedText = label.text
            resolvedFont = label.font
            resolvedColor = contentColor ?? label.textColor
        } else if let button = element as? UIButton {
            resolvedText = contentText ?? button.title(for: .normal)
            resolvedFont = contentFont ?? button.titleLabel?.font
            resolvedColor = contentColor ?? button.titleColor(for: .normal)
        } else {
            resolvedText = contentText
            resolvedFont = contentFont
            resolvedColor = contentColor
        }
        titleLabel.text = resolvedText
        titleLabel.font = resolvedFont ?? UIFont.systemFont(ofSize: 17)
        titleLabel.textColor = resolvedColor ?? .sileoLabel
        titleLabel.frame = surfaceView.contentView.bounds
        titleLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // 原控件保留布局和点击能力，文字由胶囊里的居中标签负责显示。
        if let label = element as? UILabel {
            label.textColor = .clear
        } else if let button = element as? UIButton {
            button.setTitleColor(.clear, for: .normal)
        }

        surfaceView.layoutIfNeeded()
        let contentBounds = surfaceView.contentView.bounds
        titleLabel.frame = contentBounds
        let imageViewIdentifier = "\(pinnedHeaderSurfaceIdentifier).\(identifier).Image"
        if let contentImage {
            let imageView: UIImageView
            if let existingImageView = surfaceView.contentView.subviews.first(where: {
                $0.accessibilityIdentifier == imageViewIdentifier
            }) as? UIImageView {
                imageView = existingImageView
            } else {
                let createdImageView = UIImageView()
                createdImageView.accessibilityIdentifier = imageViewIdentifier
                createdImageView.isUserInteractionEnabled = false
                createdImageView.contentMode = .scaleAspectFit
                surfaceView.contentView.addSubview(createdImageView)
                imageView = createdImageView
            }
            imageView.image = contentImage
            imageView.tintColor = contentImageTintColor
            let textWidth = min(titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                               height: titleLabel.bounds.height)).width,
                                max(0, contentBounds.width - 24))
            let groupSpacing: CGFloat = 4
            let groupWidth = textWidth + groupSpacing + 16
            let groupX = max(0, (contentBounds.width - groupWidth) / 2)
            titleLabel.textAlignment = .left
            titleLabel.frame = CGRect(x: groupX,
                                      y: 0,
                                      width: textWidth,
                                      height: contentBounds.height)
            imageView.frame = CGRect(x: groupX + textWidth + groupSpacing,
                                     y: max(0, (contentBounds.height - 16) / 2),
                                     width: 16,
                                     height: 16)
            imageView.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]
        } else if let existingImageView = surfaceView.contentView.subviews.first(where: {
            $0.accessibilityIdentifier == imageViewIdentifier
        }) {
            existingImageView.removeFromSuperview()
        }
    }

    /// iOS 26 不再使用旧版 WhiteBlur 标记，避免旧玻璃层参与顶部合成。
    static func removeLegacyBlurMarker(from viewController: UIViewController) {
        guard #available(iOS 26.0, *) else {
            return
        }
        viewController.navigationController?.navigationBar.superview?.tag = 0
    }
}
