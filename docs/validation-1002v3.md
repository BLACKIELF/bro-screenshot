# 验证说明 · 1002v3

公开版本 1.0，build 20261002.3，2026-10-02。相较 1002v2，只修改长截图完成顺序及版本标记。原位翻译实现和之前的证据见 [1002v2 验证说明](validation-1002v2.md)。当前源码输入见 [1002v3 清单](source-manifest-1002v3.json)。

原生长截图完成方法同步等待录屏停止。停止回调依赖主队列时会阻塞主线程；测试复现了这一条件。当前先异步停止流，成功后清空流并交回原生结果组装，保留复制/保存选择。停止失败不输出部分结果，重复回调被抑制，取消可继续执行。

9 项测试通过：旧阻塞条件复现、保存、复制、重复完成、无流、空结果、停止失败、移除输出失败、停止中取消。测试使用本机组件的结果组装代码并模拟 SCStream 停止回调；不创建 NSApplication 窗口、不录屏、不写通用剪贴板。这些结果只证明完成顺序，不能证明真实滚动拼接与导出图片已通过。

严格编译、完整组件接口和深度签名通过。更新本机安装包后，实际窗口显示录屏权限已获得、微信联动已启用。微信启动时 bro 主进程退出，微信菜单正常退出后恢复唯一 bro 新实例；没有点击登录、切换账号或发消息。

原生截图入口的原位翻译、长截图真实滚动和最终导出、全部标注、多屏、登录会话恢复及微信 AI 马赛克完全一致性仍未完成验收。

## 复跑完成顺序测试

需要 Apple Silicon、macOS 14.4+、Xcode 和已经正常构建安装的 `/Applications/bro截图.app`。组件接口不匹配时测试拒绝继续，不下载或分发腾讯组件。在仓库根目录执行：

```sh
long_test_dir=$(mktemp -d)
xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=14.4 \
  work/qa/test-long-completion.m work/TCSession.c work/TCOCR.m work/TCImageTranslation.m work/TCImageAnalysis.m \
  -framework Cocoa -framework Vision -framework ScreenCaptureKit -framework CoreText -framework ImageIO -framework UniformTypeIdentifiers \
  -Wl,-rpath,/Applications/bro截图.app/Contents/Frameworks -o "$long_test_dir/test-long-completion"
python3 - "$long_test_dir/test-long-completion" <<'PY'
import subprocess, sys
binary = sys.argv[1]
p = subprocess.Popen([binary, 'original-main-stop'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    out, err = p.communicate(timeout=2)
    raise AssertionError('旧阻塞条件未复现：' + out + err)
except subprocess.TimeoutExpired:
    p.terminate()
    out, err = p.communicate(timeout=2)
    assert 'ENTER original native main-thread stop' in out
    print('PASS original-main-stop: 主队列依赖条件已复现')
for mode in ('success', 'copy', 'duplicate', 'no-stream', 'empty', 'stop-error', 'remove-error', 'cancel'):
    result = subprocess.run([binary, mode], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0 and ('PASS ' + mode + ':') in result.stdout, result.stdout + result.stderr
    print(result.stdout.strip())
PY
```

完整源码编译命令仍为 `bash work/compile-source.sh`，输出目录必须不存在。测试二进制、运行日志、截图和 app 包不属于公开仓库。
