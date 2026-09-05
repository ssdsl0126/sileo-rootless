//
//  SettingsHeaderContainerView.swift
//  Sileo
//
//  Created by Skitty on 1/27/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

class SettingsHeaderContainerView: UIView {
    private var storedHeaderView: (UIView & SettingsHeaderViewDisplayable)?
    
    var headerView: (UIView & SettingsHeaderViewDisplayable)? {
        get {
            storedHeaderView
        }
        set {
            if storedHeaderView != nil {
                storedHeaderView?.removeFromSuperview()
            }
            
            storedHeaderView = newValue
            
            if newValue == nil {
                return
            }
            
            storedHeaderView?.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(storedHeaderView ?? UIView())
            
            contentBottomConstraint = storedHeaderView?.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            contentBottomConstraint?.isActive = true
            storedHeaderView?.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
            storedHeaderView?.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
            contentHeightConstraint = storedHeaderView?.heightAnchor.constraint(equalToConstant: 0)
            
            self.adjustHeaderViewHeight()
            contentHeightConstraint?.isActive = true
        }
    }
    
    var elasticHeight: CGFloat? {
        didSet {
            if contentBottomConstraint != nil {
                contentBottomConstraint?.constant = -(elasticHeight ?? 0) / 2
            }
        }
    }
    
    private var hairlineHeightConstraint: NSLayoutConstraint?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    
    private var colorInfluenceView: UIView?
    private var blurView: UIVisualEffectView?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        
        let blurView = UIVisualEffectView(effect: SileoGlass.effect(tintColor: UIColor.sileoHeaderColor,
                                                                     fallbackStyle: .light))
        blurView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        blurView.frame = self.bounds
        self.addSubview(blurView)
        self.blurView = blurView
        if #available(iOS 26.0, *) {
            // iOS 26 的导航区域由 UINavigationBar 提供玻璃，旧的整块标题 blur 会遮住它。
            blurView.effect = nil
            blurView.isHidden = true
        }
        
        let colourInfluenceView: UIView = UIView()
        colourInfluenceView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        colourInfluenceView.frame = self.bounds
        colourInfluenceView.backgroundColor = UIColor.sileoHeaderColor
        if #available(iOS 26.0, *) {
            colourInfluenceView.backgroundColor = .clear
        }
        self.addSubview(colourInfluenceView)
        
        self.colorInfluenceView = colourInfluenceView
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        
        let separatorView: UIView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = UIColor(white: 0, alpha: 0.07)
        if #available(iOS 26.0, *) {
            separatorView.isHidden = true
        }
        self.addSubview(separatorView)
        
        separatorView.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
        separatorView.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        separatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        self.hairlineHeightConstraint = separatorView.heightAnchor.constraint(equalToConstant: 1)
        self.hairlineHeightConstraint?.isActive = true
    }
    
    @objc func updateSileoColors() {
        if let blurView = blurView {
            if #available(iOS 26.0, *) {
                blurView.effect = nil
                blurView.isHidden = true
            } else {
                SileoGlass.update(blurView,
                                  tintColor: UIColor.sileoHeaderColor,
                                  fallbackStyle: .light)
            }
        }
        if #available(iOS 26.0, *) {
            colorInfluenceView?.backgroundColor = .clear
        } else {
            colorInfluenceView?.backgroundColor = UIColor.sileoHeaderColor
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if #available(iOS 26.0, *) {
            self.colorInfluenceView?.backgroundColor = .clear
        } else if #available(iOS 13.0, *) {
            self.colorInfluenceView?.backgroundColor = UIColor.sileoHeaderColor
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if hairlineHeightConstraint == nil {
            return
        }
        hairlineHeightConstraint?.constant = 1 / (self.window?.screen.scale ?? 1 as CGFloat)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.adjustHeaderViewHeight()
    }

    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        headerView?.headerHeight(forWidth: width) ?? 0
    }

    func adjustHeaderViewHeight() {
        if contentHeightConstraint == nil || headerView == nil {
            return
        }
        contentHeightConstraint?.constant = headerView?.headerHeight(forWidth: self.bounds.size.width) ?? 0
    }
}
