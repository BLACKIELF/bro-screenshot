# 验证说明 · 1002v4

公开版本 1.0，build 20261002.4，2026-10-02。相较 1002v3，将选区的“智能遮挡”改为“AI马赛克”：Apple Vision 识别人脸、手机号、邮箱和长号码，命中区域使用像素网格。检测类别和原有预览/复制/保存流程保持不变；仍不能证明与微信全部识别类别和效果一致。

网格颜色由该格所有源像素的均值生成，先裁剪再采样，保留透明度；重叠区域始终读取原图。新增颜色样本发现并修复了位图行序与 Quartz 坐标原点相反导致的取色错误。

本机已执行：

- 严格编译、完整 app 深度签名、完整私有接口校验和 24 项源码输入逐项匹配。
- 图像分析测试：真实 Vision QR 解码、空/无效输入、敏感文字输入与输出再次 OCR、普通文字/尺寸/边缘保留、无命中 TIFF 转 PNG。修复后的像素化图已目视检查。
- 像素测试：完整网格颜色均值、准确区域位置、区域外不变、上下不对称颜色、边缘裁剪、重叠区域取原色、预乘透明度。撤掉行序修复的反例被测试拒绝，保留修复的版本通过。
- 本机标准路径已更新为最终候选 r2，安装包逐文件匹配候选；联动服务正常注销再注册，主进程和代理恢复。

本轮桌面控制服务不可用，没有复验 1002v4 录屏权限、真实选区 AI 马赛克或微信启动/退出界面。1002v3 的微信联动实测仍是历史证据；当前版本的完整 GUI 闭环待重新核对。原位翻译、真实长截图、多屏、全部标注和登录会话恢复的未验项继续保留，不能宣布完整目标通过。

## 无 GUI 复跑

在仓库根目录运行，输出目录必须不存在。只处理合成样本，不录屏、不写通用剪贴板：

```sh
mosaic_test_dir=$(mktemp -d)
bash work/compile-source.sh "$mosaic_test_dir/compile"
cp "$mosaic_test_dir/compile/BroOCRHelper" "$mosaic_test_dir/BroOCRHelper"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
  work/qa/test-mosaic-pixels.m -framework Cocoa -framework Vision -framework ImageIO -framework UniformTypeIdentifiers \
  -o "$mosaic_test_dir/test-mosaic-pixels"
"$mosaic_test_dir/test-mosaic-pixels"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
  work/TCImageAnalysis.m work/TCOCR.m work/TCImageTranslation.m work/qa/test-image-analysis.m \
  -framework Cocoa -framework Vision -framework ImageIO -framework UniformTypeIdentifiers -framework CoreText -framework CoreImage \
  -o "$mosaic_test_dir/test-image-analysis"
"$mosaic_test_dir/test-image-analysis" "$mosaic_test_dir"
```

原位翻译与 helper 验证见 [1002v2](validation-1002v2.md)，长截图完成顺序验证见 [1002v3](validation-1002v3.md)。测试日志、位图、app 包和腾讯组件不属于公开仓库。
