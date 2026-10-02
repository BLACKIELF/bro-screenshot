# 验证说明 · 1002v5

公开版本 1.0，build 20261002.5，2026-10-02。相较 1002v4，局部修正截图原位翻译的渲染区域和工具栏布局，保持 Apple Vision/Translation 与既有截图流程。

旧版已复现两项问题：短译文无需换行也会清除更大的区域，擦掉旁边的色块；细长选区上下没有空位时，即使两侧可放工具栏也会盖住图片。新增测试在旧源码上分别失败，在修复后通过。

修复后先在原文字框内用 CoreText 实际排版，放得下即只覆盖该框；长译文沿用原有换行和缩字逻辑。工具栏优先放在上下或两侧的完整空位，截图坐标不变；无法完全避让时减少重叠面积。另修复深色背景回填经过颜色空间转换后变亮的问题，改用输出位图的 RGB 取色；该问题在首次候选上复现，最终 r2 的背景内外色值一致。满屏仍可能遮挡，复杂背景仍只是颜色回填，不是完整图像修复。

本机已执行：

- 短译文逐像素测试：区域内发生替换，所有区域外像素及邻近色块不变，尺寸不变；深色单色背景回填与周围像素同色。
- 工具栏测试：屏幕边缘、负坐标、窄屏、细长选区两侧避让、无法完全避让时的较小重叠。
- 真实 Vision 文字块、长译文换行、浅色/深色背景、原文替换、图像尺寸和独立图案保留；输出再次识别目标文字及对应上下位置。
- 已安装的 Apple 语言模型中英双向翻译、原位回填和译图再次 OCR，均通过。不请求模型下载，不打开 GUI，不录屏，不写通用剪贴板。
- 完整候选严格编译/链接、深度签名、完整私有接口、24 项源码输入匹配；安装包逐文件匹配候选。联动正常注销/注册，唯一主进程和代理恢复，无截图 worker。

桌面控制仍报 `codex app-server exited before returning a response`，当前版本的录屏权限、原生框选入口、工具栏实际显示与微信启动退出 GUI 闭环未复验。1002v2 的合成 GUI 和 1002v3 的微信开退实测是历史证据。原生长截图、全部标注、多屏、登录会话恢复及完整微信一致性继续未验，不能据合成测试宣布完成。

## 无 GUI 复跑

在仓库根目录运行。仅生成合成测试图，不读屏幕或剪贴板：

```sh
translation_test_dir=$(mktemp -d)
bash work/compile-source.sh "$translation_test_dir/compile"
cp "$translation_test_dir/compile/BroOCRHelper" "$translation_test_dir/BroOCRHelper"
translation_frameworks=(-framework Cocoa -framework Vision -framework ImageIO -framework CoreText -framework UniformTypeIdentifiers)
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
  "$translation_test_dir/compile/TCImageTranslation.o" work/qa/test-inline-geometry.m "${translation_frameworks[@]}" -o "$translation_test_dir/test-inline-geometry"
"$translation_test_dir/test-inline-geometry"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
  "$translation_test_dir/compile/TCImageTranslation.o" work/qa/test-translation-layout.m "${translation_frameworks[@]}" -o "$translation_test_dir/test-translation-layout"
"$translation_test_dir/test-translation-layout" "$translation_test_dir"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
  work/TCOCR.m "$translation_test_dir/compile/TCImageTranslation.o" work/qa/test-image-translation.m "${translation_frameworks[@]}" -o "$translation_test_dir/test-image-translation"
"$translation_test_dir/test-image-translation" "$translation_test_dir"
```

实际模型测试需 macOS 26+ 的公开 `installedSource` API，仅使用已有语言包；与上方测试在同一 shell 中运行，不触发下载：

```sh
xcrun swiftc -target arm64-apple-macosx15.0 -O -warnings-as-errors -parse-as-library \
  -import-objc-header work/TCImageTranslation.h work/qa/test-image-translation-live.swift "$translation_test_dir/compile/TCImageTranslation.o" \
  "${translation_frameworks[@]}" -framework Translation -framework NaturalLanguage -o "$translation_test_dir/test-image-translation-live"
"$translation_test_dir/test-image-translation-live" "$translation_test_dir"
```

测试输出、模型和日志不在仓库中。AI 马赛克验证见 [1002v4](validation-1002v4.md)，长截图完成顺序见 [1002v3](validation-1002v3.md)，既有原位翻译和 helper 说明见 [1002v2](validation-1002v2.md)。
