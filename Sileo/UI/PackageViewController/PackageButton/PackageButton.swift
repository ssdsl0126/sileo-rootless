//
//  PackageButton.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

class PackageButton: UIButton {
    private var liquidGlassBackgroundView: UIVisualEffectView?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    internal func setup() {
        if #available(iOS 26.0, *) {
            // iOS 26 的 system button 可能在初始化时自动进入 configuration 模式，清除后使用普通标题层。
            self.configuration = nil
            self.automaticallyUpdatesConfiguration = false
        }
        self.isProminent = true
        self.customAlpha = 1.0
        self.isHighlighted = false
        self.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        self.adjustsImageWhenHighlighted = false
        self.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        self.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        if #available(iOS 26.0, *) {
            // 70×32pt 是老版本按钮的最小尺寸，使用点值而不是屏幕像素。
            self.setContentHuggingPriority(.required, for: .horizontal)
            self.setContentHuggingPriority(.required, for: .vertical)
            self.setContentCompressionResistancePriority(.required, for: .horizontal)
            self.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
            self.titleLabel?.adjustsFontSizeToFitWidth = true
            self.titleLabel?.minimumScaleFactor = 0.75
        }
        tintColor = .tintColor
        self.updateStyle()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cornerRadius = min(self.bounds.width, self.bounds.height) / 2
        self.layer.cornerRadius = cornerRadius
        if #available(iOS 26.0, *) {
            if let backgroundView = liquidGlassBackgroundView {
                // titleLabel 可能在背景层创建后才加入按钮，确保玻璃始终位于最底层。
                self.sendSubviewToBack(backgroundView)
            }
            liquidGlassBackgroundView?.frame = self.bounds
            liquidGlassBackgroundView?.layer.cornerRadius = cornerRadius
            liquidGlassBackgroundView?.layer.cornerCurve = .continuous
        }
    }

    override var isHighlighted: Bool {
        didSet {
            self.updateStyle()
        }
    }
    
    public var isProminent: Bool = false {
        didSet {
            FRUIView.animate(withDuration: self.window != nil ? 0.3 : 0) {
                self.updateStyle()
            }
        }
    }
    
    private var liquidGlassNormalTitle: String?
    private var isUpdatingStyle = false
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateStyle()
    }
    
    @objc func updateSileoColors() {
        self.tintColor = .tintColor
        self.updateStyle()
    }
    
    public func updateStyle() {
        guard !isUpdatingStyle else {
            return
        }
        isUpdatingStyle = true
        defer { isUpdatingStyle = false }

        var tintColor = self.tintColor ?? .tintColor
        if self.isHighlighted {
            var tintHue: CGFloat = 0
            var tintSat: CGFloat = 0
            var tintBrightness: CGFloat = 0
            tintColor.getHue(&tintHue, saturation: &tintSat, brightness: &tintBrightness, alpha: nil)
            
            tintBrightness *= 0.75
            tintColor = UIColor(hue: tintHue, saturation: tintSat, brightness: tintBrightness, alpha: 1)
        }
        if #available(iOS 26.0, *) {
            // 标题使用普通 UIButton 绘制，玻璃只作为独立背景层，避免系统 configuration 状态机吞掉文字。
            if self.configuration != nil {
                self.configuration = nil
            }
            let backgroundView = ensureLiquidGlassBackground()
            SileoGlass.update(backgroundView,
                              interactive: true,
                              tintColor: tintColor.withAlphaComponent(0.22))
            backgroundView.backgroundColor = tintColor.withAlphaComponent(0.82)
            backgroundView.layer.cornerRadius = min(self.bounds.width, self.bounds.height) / 2
            backgroundView.layer.cornerCurve = .continuous
            backgroundView.clipsToBounds = true
            self.backgroundColor = .clear
            self.sendSubviewToBack(backgroundView)
            // 清除系统 configuration 后，iOS 26 可能仍保留隐藏的 titleLabel 状态。
            self.titleLabel?.isHidden = false
            self.titleLabel?.alpha = 1
            self.titleLabel?.textColor = .white
            self.setTitleColor(.white, for: .normal)
        } else {
            self.backgroundColor = tintColor
        }
        if #unavailable(iOS 26.0) {
            self.setTitleColor(.white, for: .normal)
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            self.alpha = isEnabled ? customAlpha * 1.0 : customAlpha * 0.45
        }
    }
    
    public var customAlpha: CGFloat = 1 {
        didSet {
            self.alpha = isEnabled ? customAlpha * 1.0 : customAlpha * 0.45
        }
    }
    
    override func setTitle(_ title: String?, for state: UIControl.State) {
        if state == .normal {
            liquidGlassNormalTitle = title
        }

        if #available(iOS 26.0, *) {
            // iOS 26 直接更新普通标题层，跳过旧版 keyframe 动画和 configuration 重建。
            super.setTitle(title, for: state)
            self.titleLabel?.isHidden = false
            self.titleLabel?.alpha = 1
            return
        }

        if title == self.title(for: state) || self.window == nil {
            super.setTitle(title, for: state)
            self.syncLiquidGlassTitle(title, for: state)
            return
        } else {
            FRUIView.animateKeyframes(withDuration: 0.25, delay: 0, options: .calculationModeCubicPaced, animations: {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                    self.titleLabel?.alpha = 0
                }
                UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.6) {
                    super.setTitle(title, for: state)
                    self.syncLiquidGlassTitle(title, for: state)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                    self.titleLabel?.isHidden = false
                    self.titleLabel?.alpha = 1
                }
            }, completion: ((Bool) -> Void)? {_ in
                    self.layoutIfNeeded()
            })
        }
    }

    func syncLiquidGlassTitle(_ title: String?, for state: UIControl.State) {
        guard state == .normal, #available(iOS 26.0, *) else {
            return
        }
        liquidGlassNormalTitle = title
    }

    @available(iOS 26.0, *)
    private func ensureLiquidGlassBackground() -> UIVisualEffectView {
        if let backgroundView = liquidGlassBackgroundView {
            backgroundView.frame = self.bounds
            return backgroundView
        }

        let backgroundView = UIVisualEffectView(effect: nil)
        backgroundView.frame = self.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundView.isUserInteractionEnabled = false
        self.insertSubview(backgroundView, at: 0)
        liquidGlassBackgroundView = backgroundView
        return backgroundView
    }
}
