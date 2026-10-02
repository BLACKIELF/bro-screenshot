"""Exercise the real helper's pipe errors and parent-death cleanup without UI."""
import argparse
import ctypes
import json
import os
import pathlib
import subprocess
import sys
import time


def executable(pid):
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    value = ctypes.create_string_buffer(4096)
    return value.value.decode() if lib.proc_pidpath(pid, value, len(value)) > 0 else None


parser = argparse.ArgumentParser()
parser.add_argument('helper', type=pathlib.Path)
parser.add_argument('report', type=pathlib.Path)
args = parser.parse_args()
helper = str(args.helper.resolve(strict=True))
assert pathlib.Path(helper).name == 'BroOCRHelper'
checks = []
for data in (b'', b'not an image'):
    result = subprocess.run([helper], input=data, capture_output=True, timeout=15)
    error = json.loads(result.stdout)['error']
    assert result.returncode == 1 and error['domain'] and error['message']
    checks.append({'input': 'empty' if not data else 'invalid', 'exit': result.returncode,
                   'errorDomain': error['domain'], 'errorCode': error['code']})

# This parent deliberately exits while its child is blocked reading stdin.
# The test process owns both pipes, and verifies executable identity before cleanup.
parent_code = '''
import os,subprocess,sys,time
child=subprocess.Popen([sys.argv[1]],stdin=int(sys.argv[2]),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print(child.pid,flush=True)
time.sleep(2)
os._exit(0)
'''
reader, writer = os.pipe()
parent = subprocess.Popen([sys.executable, '-c', parent_code, helper, str(reader)],
                          pass_fds=(reader,), stdout=subprocess.PIPE, text=True)
os.close(reader)
pid = int(parent.stdout.readline())
assert executable(pid) == helper
time.sleep(.2)
assert executable(pid) == helper  # Distinguish cleanup from a naturally short task.
parent.wait(timeout=5)
deadline = time.monotonic() + 4
while executable(pid) == helper and time.monotonic() < deadline:
    time.sleep(.05)
gone = executable(pid) != helper
os.close(writer)  # Keep EOF from ending the helper until after the guardian check.
if not gone and executable(pid) == helper:
    os.kill(pid, 15)
assert gone, 'Helper survived its parent'
checks.append({'input': 'parent exited before EOF', 'helperStartedAndStayedAlive': True,
               'helperExitedWithoutSignalFromTest': gone})
args.report.write_text(json.dumps({'passed': True, 'checks': checks}, ensure_ascii=False, indent=2)+'\n')
print('PASS OCR helper: empty/invalid input errors, live child before parent exit, automatic parent-death cleanup.')
