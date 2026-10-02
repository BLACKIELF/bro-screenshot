# 验证说明 · 1002v6

公开版本 1.0，build 20261002.6，2026-10-02。相较 1002v5，AI 马赛克留在截图编辑器，识别到的区域加入原生编辑记录，用户可继续标注、一次撤销/重做，再用原有复制或保存完成截图。取消本次识别保留原有编辑；旧任务晚返回不会改动选区。原位翻译保留 1002v5 的渲染与布局修正。

旧入口结束截图进程后另开预览，不能继续编辑。当前为每个区域保留像素化小图，复用原生移动、缩放和控制点。原生底层插入不登记撤销，因此先经正常添加登记撤销，再调整绘制顺序；已有和后加的普通标注在马赛克上方。新建矩形需要显式设置尺寸并更新控制点、路径；两项问题均在初次测试中复现，修正后通过。所有新增私有调用先核对完整 arm64 类型编码，接口变动时拒绝进入编辑器。

识别复用短时本机助手，截图经管道传递。新增马赛克模式只返回区域坐标，不返回敏感文字；保留确切系统 reader 错误的一次重试和父退出清理。截图内进度使用独立会话状态，避免父进程旧进度窗抢前台。检测范围仍是人脸、手机号、邮箱、身份证和长号码规则，不等于微信的全部识别能力；手动敏感文字标注需另行遮挡，完成前需要核对图片。

本机已执行：

- 真正的原生编辑对象，无 NSApplication/窗口：1×、2× 位置与裁切方向，先前及后续标注图层，一次 AI 撤销/重做与后续标注独立撤销，复制保留像素图，八个原生控制点和移动/尺寸状态。
- 取消后返回编辑、旧任务、新任务、重复结果、终止后的结果防护；不用通用剪贴板。
- 连续两次真实 Vision 助手识别敏感合成图，像素化后再次 OCR，敏感号码消失、公共文字保留；无命中、非法图片和越界区域。
- OCR/马赛克两种管道模式的错误、确切错误的一次重试、持续失败与永久错误，未知 CLI 参数及父退出清理。
- 全部会话监管回归，新增 M 状态心跳；8 项长截图完成回归；马赛克逐像素、短译文外部像素与深色回填、翻译工具栏几何回归。
- 最终 r2 严格编译/链接、深度签名、完整组件接口及 24 项源码输入匹配，安装包逐文件匹配。联动正常注销/注册后恢复唯一主进程和代理。

当前桌面控制报 `codex app-server exited before returning a response`。真实框选 → AI 马赛克 → 取消/撤销 → 继续标注 → 复制/保存未验；当前版本录屏权限、原位翻译实际入口和微信开退 GUI 未复验。原生长截图真实滚动、多屏、全部标注及登录会话恢复仍待验，不能据这些对象/合成测试宣布完整微信一致性。

## 无 GUI 复跑

需要 Apple Silicon、macOS 14.4+、Xcode，原生对象测试还需已正常安装的 `/Applications/bro截图.app` 和匹配组件。只生成合成图、读本机组件接口，不录屏、不开窗口、不写通用剪贴板。在仓库根目录执行：

```sh
editor_test_dir=$(mktemp -d)
bash work/compile-source.sh "$editor_test_dir/compile"
cp "$editor_test_dir/compile/BroOCRHelper" "$editor_test_dir/BroOCRHelper"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=14.4 \
  work/qa/test-editor-mosaic.m work/TCSession.c work/TCOCR.m work/TCImageTranslation.m work/TCImageAnalysis.m \
  -framework Cocoa -framework Vision -framework ScreenCaptureKit -framework CoreText -framework ImageIO -framework UniformTypeIdentifiers \
  -Wl,-rpath,/Applications/bro截图.app/Contents/Frameworks -o "$editor_test_dir/test-editor-mosaic"
"$editor_test_dir/test-editor-mosaic"
python3 work/qa/test-ocr-helper.py "$editor_test_dir/BroOCRHelper" "$editor_test_dir/helper-results.json"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -pthread work/TCSession.c work/qa/test-session.c -o "$editor_test_dir/test-session"
"$editor_test_dir/test-session"
```

其他回归复跑沿用 [1002v5](validation-1002v5.md)、[马赛克像素](validation-1002v4.md)和[长截图完成](validation-1002v3.md)。测试图、日志、组件、应用包与运行资料留在本机，仓库仅同步源码、合成测试及说明。
