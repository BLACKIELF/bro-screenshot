#!/usr/bin/python3
"""A pipe-protocol fixture; never used or bundled by the app."""
import json
import pathlib
import sys

counter = pathlib.Path('calls')
calls = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(calls))
mode = sys.stdin.buffer.read().decode()
if mode.startswith('mosaic-'):
    assert sys.argv[1:] == ['--mosaic']
    mode = mode.removeprefix('mosaic-')
else:
    assert not sys.argv[1:]
if mode == 'retry' and calls == 2:
    print(json.dumps({'regions': [{'id': '0', 'text': 'OK', 'x': .1, 'y': .2, 'width': .3, 'height': .4}]}))
else:
    recoverable = mode in ('retry', 'persistent')
    print(json.dumps({'error': {'domain': 'TextRecognition.CRImageReaderError' if recoverable else 'FixturePermanentError',
                              'code': 1 if recoverable else 3, 'message': 'Synthetic failure'}}))
    sys.exit(1)
