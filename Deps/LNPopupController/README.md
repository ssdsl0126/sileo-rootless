# LNPopupController

SwiftPM 源码来自 `elihwyma/LNPopupController` 的 `6cdb4a977b8e0253305cd5009e33028d90631788`，授权见 `LICENSE`。

Sileo 在 iOS 27 的 iPhone 上使用系统底部标签栏时，旧弹层未挂载且没有显示或正在呈现时，把标签栏的层级交给 UIKit。修改位于 `UIViewController+LNPopupSupportPrivate.m` 的 `_layoutPopupBarOrderForUse`。
