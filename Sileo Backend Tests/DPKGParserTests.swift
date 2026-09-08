//
//  DPKGParserTests.swift
//  Sileo Backend Tests
//
//  Created by Amy While on 23/03/2023.
//  Copyright © 2023 Sileo Team. All rights reserved.
//

import XCTest
@testable import Sileo

final class DPKGParserTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAMaintainerParser() throws {
        let case1 = "Amy While <me@anamy.gay>"
        let case2 = "Amy While"
        let case3 = "Amy While <me@anamy.gay"
        
        let case1Maintainer = Maintainer(string: case1)
        XCTAssert(case1Maintainer.name == "Amy While" && case1Maintainer.email == "me@anamy.gay", "Failed to parse \(case1)")
        let case2Maintainer = Maintainer(string: case2)
        XCTAssert(case2Maintainer.name == "Amy While" && case2Maintainer.email == nil, "Failed to parse \(case2)")
        let case3Maintainer = Maintainer(string: case3)
        XCTAssert(case3Maintainer.name == "Amy While" && case3Maintainer.email == nil, "Failed to parse \(case3), got: \(dump(case3Maintainer))")
    }

    func testPackageIndexFormatValidatorRejectsHTMLFallback() {
        let html = Data("<!DOCTYPE html><html></html>".utf8)
        for fileExtension in ["zst", "xz", "lzma", "bz2", "gz", ""] {
            XCTAssertFalse(PackageIndexFormatValidator.matches(html, fileExtension: fileExtension))
        }
    }

    func testPackageIndexFormatValidatorRecognizesSupportedFormats() {
        XCTAssertTrue(PackageIndexFormatValidator.matches(Data([0x28, 0xB5, 0x2F, 0xFD]), fileExtension: "zst"))
        XCTAssertTrue(PackageIndexFormatValidator.matches(Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]), fileExtension: "xz"))
        XCTAssertTrue(PackageIndexFormatValidator.matches(Data([0x5D, 0x00, 0x00, 0x80, 0x00] + Array(repeating: 0xFF, count: 8)), fileExtension: "lzma"))
        XCTAssertTrue(PackageIndexFormatValidator.matches(Data([0x42, 0x5A, 0x68]), fileExtension: "bz2"))
        XCTAssertTrue(PackageIndexFormatValidator.matches(Data([0x1F, 0x8B]), fileExtension: "gz"))
        XCTAssertTrue(PackageIndexFormatValidator.matches(Data("Package: test\nVersion: 1.0\n".utf8), fileExtension: ""))
    }

}
