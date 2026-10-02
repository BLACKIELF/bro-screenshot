# 验证说明 · 1002v7

公开版本 1.0，build 20261002.7，2026-10-02。相较 1002v6，长译文也在原文字框内换行、缩字，避免扩大回填区域擦掉附近图标和线条；过长内容仍明确提示放不下。原位译文、切换目标语言、查看原图和复制/保存入口保持原有流程。

旧版只保护能放下的短译文，长译文会向右、向下扩大回填。带相邻红色图标和蓝色线条的合成图在旧源码上确实失败；最小修正为所有译文使用原框，仍由同一个 CoreText 排版结果判断完整文字是否可见。短句、长句、全部框外像素、邻近图案、深色回填和超长错误分支通过。OCR 验收允许正常换行，仍要求完整英文末尾和替换结果存在。

本机已执行：

- 真实 Vision 文字框 → 原位译文绘制 → 译图再次 OCR，中英位置、原文替换、长句完整换行、尺寸与图案保留通过。
- 已安装的 Apple 语言模型中英双向批量翻译、原位译图及结果 OCR 通过。未请求语言包下载。
- 实际原生 `imageEdited` 和 `captureDidFinish:` 方法，无界面的合成视图：1×/2× 逻辑尺寸，马赛克与先前/后续标注层级，全部未选中像素、复制/保存回调参数、PNG 回读、逐像素组撤销/重做及后续标注独立撤销/重做通过。AppKit 缓存可初始化 NSApplication，但没有窗口、激活、事件循环、录屏、输入注入、保存面板或通用剪贴板操作。
- 严格编译/链接、深度签名、完整组件接口、24 项构建输入和安装包逐文件匹配。安装前查重；联动正常注销/注册后恢复唯一主进程和代理，保留 1002v6 最终版回退。

以上原生方法测试不等于用户点击复制或保存的 GUI 验收。当前桌面控制仍报 `codex app-server exited before returning a response`。真实框选、当前录屏权限、原位翻译入口和微信开退 GUI 未复验；真实长截图、多屏、全部标注与登录恢复仍待验，完整功能目标未完成。其他实现和回归边界见 [1002v6](validation-1002v6.md)。

## 无 GUI 复跑

需要 Apple Silicon、macOS 14.4+、Xcode 和已正常安装的匹配组件。实际模型测试另需 macOS 26+ 及已安装中英语言包；产品通过 SwiftUI 支持 macOS 15+ 的系统同意流程。

在仓库根目录执行：

```sh
export_test_dir=$(mktemp -d)
bash work/compile-source.sh "$export_test_dir/compile"
cp "$export_test_dir/compile/BroOCRHelper" "$export_test_dir/BroOCRHelper"
translation_frameworks=(-framework Cocoa -framework Vision -framework CoreText -framework ImageIO -framework UniformTypeIdentifiers)
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=14.4 \
  work/qa/test-translation-layout.m "$export_test_dir/compile/TCImageTranslation.o" "${translation_frameworks[@]}" -o "$export_test_dir/test-translation-layout"
"$export_test_dir/test-translation-layout" "$export_test_dir"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=14.4 \
  work/qa/test-image-translation.m work/TCOCR.m "$export_test_dir/compile/TCImageTranslation.o" "${translation_frameworks[@]}" -o "$export_test_dir/test-image-translation"
"$export_test_dir/test-image-translation" "$export_test_dir"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=14.4 \
  work/qa/test-editor-export.m work/TCSession.c work/TCOCR.m work/TCImageTranslation.m work/TCImageAnalysis.m \
  "${translation_frameworks[@]}" -framework ScreenCaptureKit -Wl,-rpath,/Applications/bro截图.app/Contents/Frameworks -o "$export_test_dir/test-editor-export"
"$export_test_dir/test-editor-export"
```

已有中英模型的本机测试，与上方在同一 shell 中运行，不触发下载：

```sh
xcrun swiftc -target arm64-apple-macosx15.0 -O -warnings-as-errors -parse-as-library \
  -import-objc-header work/TCImageTranslation.h work/qa/test-image-translation-live.swift "$export_test_dir/compile/TCImageTranslation.o" \
  "${translation_frameworks[@]}" -framework Translation -framework NaturalLanguage -o "$export_test_dir/test-image-translation-live"
"$export_test_dir/test-image-translation-live" "$export_test_dir"
```

仓库仅同步源码、合成测试和说明；不分发腾讯组件、应用包、截图、运行日志或本机反汇编资料。
