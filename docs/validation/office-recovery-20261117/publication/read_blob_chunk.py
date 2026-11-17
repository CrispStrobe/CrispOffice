import base64
import re
import subprocess
import sys

sha, start, length = sys.argv[1:]
assert re.fullmatch('[0-9a-f]{40}', sha)
start, length = int(start), int(length)
assert start >= 0 and 0 < length <= 24576
data = subprocess.check_output(['git', 'cat-file', 'blob', sha])
print(base64.b64encode(data[start:start + length]).decode())
