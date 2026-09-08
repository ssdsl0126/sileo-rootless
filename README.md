# Sileo
[![Build](https://github.com/Sileo/Sileo/actions/workflows/main.yml/badge.svg)](https://github.com/Sileo/Sileo/actions/workflows/main.yml)

A modern APT package manager frontend

# Info

Sileo focuses on speed, features, and a modern feel. It is made with love by people from all over the world!

Our official Twitter is [@GetSileo](https://twitter.com/getsileo).

# Support

For support, ask in the [Sileo Discord server](https://discord.com/invite/Udn4kQg) or contact [@SileoSupport on Twitter](https://twitter.com/sileosupport).

# Support the project 

If you would like to help support the development of Sileo, consider donating at the following links:

* Amy (Sileo Developer): [Patreon](https://www.patreon.com/elihwyma), [Paypal](https://paypal.me/anamy1024)
* Aarnav (Canister Developer/Maintainer): [Github Sponsors](https://github.com/sponsors/tale), [Patreon](https://www.patreon.com/aarnavtale), [Paypal](https://paypal.me/aatale)

# 构建未签名 Sileo Demo IPA

安装可编译当前代码的完整 Xcode（当前代码使用 iOS 27 SDK），完成首次启动设置，并确保 Git 子模块已拉取后，在项目根目录执行：

```sh
make
# 等价命令：make demo 或 make demo-ipa
```

默认构建 iPhone/iPad 的 arm64 Release 版本，输出 `packages/Sileo-Demo_<版本号>-unsigned.ipa`。无需配置开发者团队、证书、描述文件，也不依赖 `ldid` 或 `dpkg`。IPA 内保留应用所需框架，清除签名及描述文件，可交给支持导入未签名 IPA 的签名工具签名安装。

构建默认使用两个并行任务，可通过 `DEMO_JOBS` 调整；`DEBUG=1` 可构建 Debug 版本。构建缓存默认位于 `build/demo-ipa`，可通过 `DEMO_DERIVED_DATA_PATH` 修改；输出目录可通过 `DEMO_OUTPUT_DIR` 修改。例如指定 Xcode：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make demo-ipa
```

越狱版 `.deb` 仍使用原有命令，例如 `make package SILEO_PLATFORM=iphoneos-arm64`。

# Contribute

For localization, [join our Crowdin project](https://crowdin.com/project/sileo) and submit your translations there.

For software, make a Pull Request with your changes and our team will review it.

1. Clone this repository
    ```sh
    git clone --recursive https://github.com/Sileo/Sileo
    ```
2. Set the `DEVELOPMENT_TEAM` Build Setting
    
    There are multiple ways to do this, for example:
    
    * Using Xcode Custom Paths
        * Go to Xcode > Preferences > Locations > Custom Paths
        * Add an entry with `Name` as `DEVELOPMENT_TEAM`, `Display Name` as `Development Team`, and `Path` as your Apple Developer Team ID
    * Using Xcode Build Settings
        * Set the `Development Team` Build Setting
        * Remember to never commit this change
        
3. Apply our git hooks by running: `git config core.hooksPath .githooks`
4. Open `Sileo.xcodeproj` and have at it!

If you have questions, ask in the Sileo Discord server.

#

Sileo Team 2018 - 2023
