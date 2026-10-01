# 验证说明 · 1001v1

公开版本：1.0。记录日期：2026-10-01。对应内部验收源码为 1001v8 / 1.8.7 / 20261001.8。

本次发布的 17 项应用输入逐项匹配已严格编译、签名及完整接口校验的本机 1001v8 构建清单。应用源码没有因上传而修改。发布目录还包含四个可复跑的合成测试；本机验收图片、进程身份和私有日志没有放入仓库。

推送前已从此发布目录重新完成严格源码编译/链接，并运行下方四项合成测试，全部通过。26 个待上传文件的范围、21 项源码/测试输入哈希及文档相对链接均已核对；未发现凭据或个人本机路径。

已完成的本机 GUI 检查：微信开/退联动，微信已运行时手动打开工具，说明 modal 打开时退出，联动关闭后重启保持关闭，重新启用后恢复，取消截图保持剪贴板。应用图标在系统录屏列表中正常显示。检查没有登录或切换账号、发送消息、登出登录会话或重启系统。

此前版本已有截图/传统马赛克、实图 OCR 和实际英文译文的成功记录；1001v8 未进行全部回归。直接置顶只完成代码、编译和私有接口校验；本轮截图取消，没有取得置顶结果，不能记为通过。长截图、二维码、全部标注及最终保存、多屏和登录会话恢复仍有未验项，AI 一键马赛克尚未实现。

## 无 GUI 测试

在仓库根目录运行，以下输出只写到临时测试目录：

```sh
test_dir=$(mktemp -d)
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -pthread work/TCSession.c work/qa/test-session.c -o "$test_dir/test-session"
"$test_dir/test-session"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 -framework Cocoa -framework Vision -framework CoreText work/TCOCR.m work/qa/test-ocr.m -o "$test_dir/test-ocr"
"$test_dir/test-ocr"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror work/TCLifecyclePolicy.c work/qa/acceptance-0930v1/lifecycle-policy-test.c -o "$test_dir/test-policy"
"$test_dir/test-policy"
xcrun clang -arch arm64 -std=c11 -O2 -Wall -Wextra -Werror -c work/TCLifecyclePolicy.c -o "$test_dir/lifecycle-policy.o"
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -framework Cocoa -framework ServiceManagement work/TCLifecycleAgent.m "$test_dir/lifecycle-policy.o" work/qa/acceptance-0930v1/lifecycle-event-test.m -o "$test_dir/test-events"
"$test_dir/test-events"
```

会话测试使用短命合成 worker；OCR 在离屏位图上识别 HELLO 2026；生命周期事件测试只调用自身测试对象。它们不启动截图 GUI、不操作第三方应用或修改录屏授权，也不替代实际桌面验收。
