# 验证说明 · 1002v2

公开版本 1.0，内部 build 20261002.2，记录日期 2026-10-02。相较首次发布增加截图原位翻译、选区分析、贴图比例保护和相应测试。24 项应用输入逐项匹配本机最终构建；严格编译、完整组件接口、深度签名及现有授权的签名指定要求匹配通过。

本机完整链通过：真实 Vision 文字位置 → 已安装 Apple 中英语言模型批量翻译 → CoreText 译图 → 再次识别译图。核对文字位置、浅色/深色背景、长译文换行、图像尺寸和非文字色块。翻译只匹配原文字块的标识，重复和缺失响应会报错。

合成 GUI 已检查：立即显示进度、识别时取消、取消后重试、目标语言切换后自动更新、原图开关、返回、连续重开、复制和保存动作回传有效 PNG。测试回调只向测试目录导出图片，不写通用剪贴板；不能据此宣称原生截图的实际剪贴板/保存面板已验收。原生选区坐标和最终导出仍待实体操作核对。

此主机的同进程连续 Vision 请求曾复现识别失败。改为每次请求启动短时 helper；退出仅处理自己的 helper，父进程消失后自动退出。真实连续请求通过。后续出现一次 `TextRecognition.CRImageReaderError` code 1，人工重试成功；对此错误自动重试一次，其他错误不重试。合成协议测试确认最多两次、持续失败仍报错、永久错误只运行一次。错误输入和父退出守护实测通过。

更新到本机标准路径后，应用实际显示录屏权限已获得、微信联动已启用；微信正常启动时 bro 主进程退出，微信菜单正常退出后恢复唯一 bro 实例。没有点击登录、切换账号、发消息、注销账号或重启系统。

原生长截图、全部标注、多屏和登录会话恢复等仍未完成验收。智能遮挡只覆盖明确的识别类别，不能保证覆盖所有隐私信息或达到微信 AI 马赛克全部效果；复杂图片背景的原位回填也存在限制。macOS 15+ 的 GUI 翻译和语言包首次下载分支未在其他系统版本验收。

## 无 GUI 复跑

在仓库根目录运行；只使用合成位图和短时本机测试任务：

```sh
test_dir=$(mktemp -d)
bash work/compile-source.sh "$test_dir/compile"
cp "$test_dir/compile/BroOCRHelper" "$test_dir/BroOCRHelper"
image_frameworks=(-framework Cocoa -framework Vision -framework ImageIO -framework CoreText -framework UniformTypeIdentifiers)
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 work/TCOCR.m "$test_dir/compile/TCImageTranslation.o" work/qa/test-ocr.m "${image_frameworks[@]}" -o "$test_dir/test-ocr"
"$test_dir/test-ocr"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 work/TCOCR.m "$test_dir/compile/TCImageTranslation.o" work/qa/test-image-translation.m "${image_frameworks[@]}" -o "$test_dir/test-image-translation"
"$test_dir/test-image-translation" "$test_dir"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 "$test_dir/compile/TCImageTranslation.o" work/qa/test-inline-geometry.m "${image_frameworks[@]}" -o "$test_dir/test-inline-geometry"
"$test_dir/test-inline-geometry"
python3 work/qa/test-ocr-helper.py "$test_dir/BroOCRHelper" "$test_dir/helper-lifecycle.json"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -pthread work/TCSession.c work/qa/test-session.c -o "$test_dir/test-session"
"$test_dir/test-session"
```

实际中英翻译测试只使用已有语言模型，不请求下载、不打开 GUI；需 macOS 26+ 的公开 `installedSource` API：

```sh
xcrun swiftc -target arm64-apple-macosx15.0 -O -warnings-as-errors -parse-as-library -import-objc-header work/TCImageTranslation.h work/qa/test-image-translation-live.swift "$test_dir/compile/TCImageTranslation.o" "${image_frameworks[@]}" -framework Translation -framework NaturalLanguage -o "$test_dir/test-image-translation-live"
"$test_dir/test-image-translation-live" "$test_dir"
```

`BroOCRHelper` 必须与调用测试二进制放在同一目录；应用包由构建脚本保证这个关系。测试输出和缓存不属于发布文件。
