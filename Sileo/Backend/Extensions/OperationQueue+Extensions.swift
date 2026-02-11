//
//  OperationQueue+Extensions.swift
//  Sileo
//
//  Created by Amy While on 14/04/2023.
//  Copyright © 2023 Sileo Team. All rights reserved.
//

import Foundation

extension OperationQueue {
    
    convenience init(name: String, serial: Bool) {
        self.init()
        self.name = name
        if serial {
            self.maxConcurrentOperationCount = 1
        }
    }
    
    convenience init(name: String, maxConcurrent: Int) {
        self.init()
        self.name = name
        self.maxConcurrentOperationCount = maxConcurrent
    }
    
}
