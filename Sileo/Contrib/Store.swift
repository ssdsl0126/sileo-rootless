//
//  Store.swift
//  Sileo
//
//  Created by CoolStar on 9/10/16.
//  Copyright © 2016 CoolStar. All rights reserved.
//

import Foundation

// swiftlint:disable all
let StoreEndpoint = "https://featuredpage.getsileo.app/"
let StoreVersion = "0.7.1"

func StoreURL(_ relativePath: String) -> URL? {
    URL(string: StoreEndpoint.appending(relativePath))
}

// swiftlint:enable all
