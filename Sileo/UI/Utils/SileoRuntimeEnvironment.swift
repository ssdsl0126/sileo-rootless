//
//  SileoRuntimeEnvironment.swift
//  Sileo
//

import Foundation
import MachO

enum SileoRuntimeEnvironment {
    static let hasThirdPartyTweakInjection: Bool = {
        let imageCount = _dyld_image_count()
        guard imageCount > 0 else {
            return false
        }

        for imageIndex in 0..<imageCount {
            guard let imageName = _dyld_get_image_name(imageIndex) else {
                continue
            }

            if String(cString: imageName).contains("/TweakInject/") {
                return true
            }
        }

        return false
    }()

    static var isLargeTitleMarginNormalizationDisabled: Bool {
        UserDefaults.standard.bool(forKey: "DisableLargeTitleMarginNormalization")
    }

    #if DEBUG
    private static var didLogUserDefaultsDisable = false
    private static var didLogTweakInjectionDisable = false
    #endif

    static func logLargeTitleMarginNormalizationDisabledByUserDefaultsIfNeeded() {
        #if DEBUG
        guard !didLogUserDefaultsDisable else {
            return
        }
        didLogUserDefaultsDisable = true
        print("[Sileo] Large title margin normalization disabled by UserDefaults key 'DisableLargeTitleMarginNormalization'.")
        #endif
    }

    static func logLargeTitleMarginNormalizationDisabledByTweakInjectionIfNeeded() {
        #if DEBUG
        guard !didLogTweakInjectionDisable else {
            return
        }
        didLogTweakInjectionDisable = true
        print("[Sileo] Large title margin normalization skipped because third-party tweak injection was detected.")
        #endif
    }
}
