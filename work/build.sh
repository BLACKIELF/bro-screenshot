#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source_frameworks='/Applications/QQ.app/Contents/Resources/app/QQ ScreenCapture plugin.app/Contents/Frameworks'
# Reject existing output: process enumeration can be unavailable in the sandbox.
mkdir -p candidates
if [[ $# -gt 0 ]]; then
    candidate_dir="$1"
    mkdir "$candidate_dir" || { echo '拒绝覆盖已存在的候选目录。' >&2; exit 1; }
else
    candidate_dir=$(mktemp -d "$PWD/candidates/1002v3-$(date +%Y%m%d-%H%M%S)-XXXXXX")
fi
output="$candidate_dir/bro截图.app"
for framework in JietuFramework CocoaLumberjack AFNetworking; do
    test -d "$source_frameworks/$framework.framework" || { echo "本机 QQ 缺少截图组件：$framework" >&2; exit 1; }
    /usr/bin/codesign --verify --strict "$source_frameworks/$framework.framework"
done
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources" "$output/Contents/Frameworks" "$output/Contents/Library/LaunchAgents"
for framework in JietuFramework CocoaLumberjack AFNetworking; do
    /usr/bin/ditto "$source_frameworks/$framework.framework" "$output/Contents/Frameworks/$framework.framework"
done
bash compile-source.sh "$candidate_dir/source-compile"
cp "$candidate_dir/source-compile/TencentCapture.compile-check" "$output/Contents/MacOS/TencentCapture"
cp "$candidate_dir/source-compile/BroOCRHelper" "$output/Contents/MacOS/BroOCRHelper"
/usr/bin/codesign --sign "${TC_SIGN_IDENTITY:--}" "$output/Contents/MacOS/BroOCRHelper"
bash make-app-icon.sh "$candidate_dir/icon-build"
cp "$candidate_dir/icon-build/AppIcon.icns" "$output/Contents/Resources/AppIcon.icns"
python3 - "$output/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump({
      'CFBundleIdentifier':'local.yichen.TencentCapture',
      'CFBundleExecutable':'TencentCapture',
      'CFBundleName':'bro截图', 'CFBundleDisplayName':'bro截图',
      'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'1.0',
      'CFBundleVersion':'20261002.3', 'LSMinimumSystemVersion':'14.4',
      'CFBundleIconFile':'AppIcon.icns',
      'LSUIElement':True, 'NSHighResolutionCapable':True,
      'NSPrincipalClass':'NSApplication',
      'NSScreenCaptureUsageDescription':'采集屏幕，在本机标注、复制、保存和识别文字。',
    }, f)
PY
python3 - "$output/Contents/Library/LaunchAgents/local.yichen.TencentCapture.Lifecycle.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump({
      'Label':'local.yichen.TencentCapture.Lifecycle',
      'BundleProgram':'Contents/MacOS/TencentCapture',
      'ProgramArguments':['Contents/MacOS/TencentCapture','--lifecycle-agent'],
      'RunAtLoad':True,
      'KeepAlive':True,
      'ProcessType':'Background',
    }, f)
PY
# Preserve baseline ad-hoc signing policy and original embedded signatures.
# Changed cdhash may require normal macOS reauthorization. Never alter TCC.
/usr/bin/codesign --sign "${TC_SIGN_IDENTITY:--}" "$output"
/usr/bin/codesign --verify --deep --strict "$output"
/usr/bin/codesign -dv --verbose=4 "$output" 2> "$candidate_dir/signature.txt"
python3 - "$candidate_dir" "$source_frameworks" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); source=pathlib.Path(sys.argv[2]); app=root/'bro截图.app'
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
files={n:digest(pathlib.Path(n)) for n in ('main.m','TCWorker.m','TCWorker.h','TCSession.c','TCSession.h','TCHotkeyGate.h','TCOCR.m','TCOCR.h','TCImageAnalysis.m','TCImageAnalysis.h','TCImageTranslation.m','TCImageTranslation.h','TCImageTranslation.swift','TCImageOCRHelper.m','TCPinGeometry.h','TCTranslation.swift','TCTranslation.h','TCLifecycleAgent.h','TCLifecycleAgent.m','TCLifecyclePolicy.c','compile-source.sh','build.sh','make-app-icon.sh','assets/app-icon-1001v1.png')}
frameworks={}
for name in ('JietuFramework','CocoaLumberjack','AFNetworking'):
    relative=pathlib.Path(name+'.framework')/'Versions'/'A'/name
    src=digest(source/relative); dst=digest(app/'Contents'/'Frameworks'/relative)
    assert src==dst, name
    frameworks[name]={'sha256':src,'sourceMatches':True}
(root/'manifest.json').write_text(json.dumps({'version':'1002v3-candidate','app':str(app.resolve()),'sourceSHA256':files,'frameworks':frameworks,'helperSHA256':digest(app/'Contents/MacOS/BroOCRHelper'),'appIconSHA256':digest(app/'Contents'/'Resources'/'AppIcon.icns'),'guiTested':False,'installed':False},ensure_ascii=False,indent=2)+'\n')
print(str(app.resolve()))
PY
# Do not open GUI or invoke screen capture here.
