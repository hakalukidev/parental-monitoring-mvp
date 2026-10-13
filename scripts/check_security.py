"""Check the current tracked source, printing filenames/rule names only (never secret values)."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
errors = []
for filename in files:
    if not filename or filename.startswith('backend/node_modules/'): continue
    path = root / filename
    if not path.exists(): continue
    if path.suffix in {'.jks', '.keystore'} or path.name == '.env' or path.name == 'key.properties':
        errors.append((filename, 'private material is tracked')); continue
    if path.suffix not in {'.kt', '.kts', '.dart', '.ts', '.md', '.yaml', '.yml', '.json', '.example'}: continue
    source = path.read_text(errors='ignore')
    for rule, expression in [
        ('certificate bypass', r'badCertificateCallback\s*='),
        ('hostname bypass', r'hostnameVerifier\s*\{'),
        ('embedded signing password', r'(?:storePassword|keyPassword)\s*=\s*"[^"\n]+"'),
        ('embedded JWT/service secret', r'(?:JWT_ACCESS_SECRET|JWT_REFRESH_SECRET|SESSION_TOKEN_SECRET|PARENT_CHILD_API_TOKEN)\s*=\s*(?!replace)[^\s#]{10,}'),
        ('private key', r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    ]:
        if re.search(expression, source): errors.append((filename, rule))
for filename, rule in errors: print(f'{filename}: {rule}')
if errors: sys.exit(1)
print('Tracked-source security checks passed. This is a regression guard, not a full historical secret audit.')
