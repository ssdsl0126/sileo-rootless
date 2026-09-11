//
//  CollectionViewTableViewCell.swift
//  Sileo
//
//  Created by Skitty on 1/26/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

class CollectionViewTableViewCell: UITableViewCell {
    private var collectionView: UICollectionView
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init(style: UITableViewCell.CellStyle.default, reuseIdentifier: "collectionCell")
        
        self.selectionStyle = UITableViewCell.SelectionStyle.none
        self.clipsToBounds = true

        if #available(iOS 26.0, *) {
            // 内嵌列表透明时，容器也要透出设置页的弹窗底色。
            self.backgroundColor = .clear
            self.contentView.backgroundColor = .clear
            self.isOpaque = false
        }
        
        self.collectionView.isScrollEnabled = false
        self.addSubview(self.collectionView)
    }
    
    override func systemLayoutSizeFitting(_ targetSize: CGSize,
                                          withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize {
        collectionView.removeFromSuperview()
        collectionView.frame = CGRect(x: 0, y: 0, width: self.bounds.size.width, height: CGFloat(MAXFLOAT))
        self.layoutIfNeeded()
        
        let size: CGSize = collectionView.collectionViewLayout.collectionViewContentSize
        collectionView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        self.addSubview(collectionView)
        
        return size
    }
}
