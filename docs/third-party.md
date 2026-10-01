# 组件和交互来源

## 本机运行依赖

- `JietuFramework.framework`：本机 QQ 提供的原生截图编辑器，使用私有接口，并在运行前校验完整 arm64 方法编码。
- `CocoaLumberjack.framework`、`AFNetworking.framework`：上述组件所需的本机运行依赖。
- Apple AppKit、ScreenCaptureKit、Vision、ServiceManagement、SwiftUI 和 Translation：系统/SDK框架。

构建脚本读取的路径为 `/Applications/QQ.app/Contents/Resources/app/QQ ScreenCapture plugin.app/Contents/Frameworks`。构建时保留原组件签名并执行严格校验。本仓库没有复制、上传或发布任何腾讯框架或其他第三方运行二进制，也没有修改 QQ/微信应用或聊天数据。

## 交互研究

贴图行为参考了以下项目的源码，应用中的选区置顶和图片窗口由本项目用 AppKit 编写，没有把它们的 GPL 源码纳入应用：

- [Flameshot pinwidget.cpp](https://github.com/flameshot-org/flameshot/blob/2d478061ffeeba5919d3a3d9168f93542ea9b357/src/tools/pin/pinwidget.cpp)：置顶、拖动、缩放和关闭交互。
- [ksnip PinWindow.cpp](https://github.com/ksnip/ksnip/blob/343925d24bb0031e636013773fd310e9c56315b9/src/gui/modelessWindows/pinWindow/PinWindow.cpp)：无边框贴图、拖动、双击/Esc与右键关闭。
- [eSearch clip_window.ts](https://github.com/xushengfeng/eSearch/blob/dcc2222e5bb9b6f51e89210b6ce48a7dc9d3c1ec/src/renderer/clip/clip_window.ts)和[ding.ts](https://github.com/xushengfeng/eSearch/blob/dcc2222e5bb9b6f51e89210b6ce48a7dc9d3c1ec/src/renderer/ding/ding.ts)：对照选区、长截图及贴图状态；未移植它的实现。

较早的入口参考：[QQ-capture-screen-on-mac](https://github.com/isee15/QQ-capture-screen-on-mac)。历史示例不能证明当前 macOS 或当前组件兼容。
