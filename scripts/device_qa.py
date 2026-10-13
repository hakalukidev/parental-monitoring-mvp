"""Drive isolated .qa apps against the private local fixture on an explicitly selected device."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('--serial', required=True)
p.add_argument('--action', choices=['child-login', 'parent-login', 'start-child', 'start-parent', 'dump', 'tap', 'screenshot', 'status', 'scroll'], required=True)
p.add_argument('--text')
p.add_argument('--output')
p.add_argument('--index',type=int,default=-1)
a = p.parse_args()
if not re.fullmatch(r'(?:emulator-\d+|adb-07565251A8001325-[A-Za-z0-9]+\._adb-tls-connect\._tcp)', a.serial): raise SystemExit('Only the QA emulator or explicitly authorized Infinix is allowed')
root = Path(__file__).resolve().parents[1]
fixture = json.loads(Path('/private/tmp/seftly-device-fixture.json').read_text())

def adb(*args, binary=False):
    result = subprocess.run([str(Path.home()/'Library/Android/sdk/platform-tools/adb'), '-s', a.serial, *args], check=True, capture_output=True)
    return result.stdout if binary else result.stdout.decode(errors='replace')

def start(kind):
    pkg = f'com.example.{"childapp" if kind == "child" else "parent_app"}.qa'
    activity = 'com.example.childapp.ui.MainActivity' if kind == 'child' else 'com.example.parent_app.MainActivity'
    adb('shell', 'am', 'start', '-n', f'{pkg}/{activity}')
    time.sleep(2)

def nodes():
    windows = adb('shell', 'dumpsys', 'window')
    focus = [line for line in windows.splitlines() if 'mCurrentFocus=' in line or 'mFocusedWindow=' in line]
    allowed = ('com.example.parent_app.qa/', 'com.example.childapp.qa/', 'dev.seftly.notificationfixture/', 'com.android.settings/', 'com.android.permissioncontroller/', 'com.google.android.permissioncontroller/', 'com.google.android.permissioncontroller.', 'com.android.systemui/.media.MediaProjectionPermissionActivity')
    if not focus or not any(any(pkg in line for pkg in allowed) for line in focus):
        raise SystemExit('QA window is not focused; refusing to inspect private overlays or other apps')
    foreground = adb('shell', 'dumpsys', 'activity', 'activities')
    visible = [line for line in foreground.splitlines() if 'ResumedActivity:' in line or 'topResumedActivity=' in line]
    if not any(any(pkg in line for pkg in ('com.example.parent_app.qa/', 'com.example.childapp.qa/', 'dev.seftly.notificationfixture/', 'com.android.settings/', 'com.android.permissioncontroller/', 'com.google.android.permissioncontroller/', 'com.google.android.permissioncontroller.', 'com.android.systemui/.media.MediaProjectionPermissionActivity')) for line in visible):
        raise SystemExit('Refusing to inspect or interact with a production/private app')
    adb('shell', 'uiautomator', 'dump', '/sdcard/seftly-qa-window.xml')
    source = adb('shell', 'cat', '/sdcard/seftly-qa-window.xml')
    return list(ET.fromstring(source).iter('node'))

def tap_node(node):
    x1,y1,x2,y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)); time.sleep(.4)

def tap_text(text):
    all_nodes = nodes()
    candidates = [n for n in all_nodes if text.casefold() == (n.get('text','')+' '+n.get('content-desc','')).strip().casefold()]
    if not candidates: candidates = [n for n in all_nodes if text.casefold() in (n.get('text','')+' '+n.get('content-desc','')).casefold()]
    if not candidates: raise SystemExit(f'QA control not visible: {text}')
    tap_node(candidates[a.index])

if a.action.startswith('start-'): start(a.action.split('-')[1]); print('Debug app opened')
elif a.action.endswith('-login'):
    kind = a.action.split('-')[0]; start(kind)
    fields = [n for n in nodes() if n.get('class') == 'android.widget.EditText']
    deadline = time.monotonic() + 10
    while len(fields) < 2 and time.monotonic() < deadline:
        time.sleep(.5)
        fields = [n for n in nodes() if n.get('class') == 'android.widget.EditText']
    if len(fields) < 2: raise SystemExit('QA login fields are not visible')
    for index,value in enumerate([fixture['username'] if kind=='child' else fixture['email'], fixture['password']]):
        # The keyboard can move the second field on short displays.
        visible_fields = [n for n in nodes() if n.get('class') == 'android.widget.EditText']
        if len(visible_fields) < 2: raise SystemExit('QA login fields moved out of view')
        tap_node(visible_fields[index]); adb('shell','input','text',value)
        adb('shell', 'input', 'keyevent', '4'); time.sleep(.4)
    tap_text('Connect with my family' if kind=='child' else 'Sign in to Seftly'); time.sleep(3)
    print('Submitted isolated fixture login')
elif a.action == 'scroll':
    nodes()
    for _ in range(max(1,min(a.index,12))): adb('shell','input','swipe','500','1700','500','450','350')
    print('QA view scrolled')
elif a.action == 'tap': tap_text(a.text); print('QA control tapped')
elif a.action == 'dump':
    for n in nodes():
        if n.get('password') == 'true': continue
        text = (n.get('text','')+' '+n.get('content-desc','')).strip()
        if text and fixture['password'] not in text: print(text[:700], n.get('bounds'))
elif a.action == 'screenshot':
    nodes()
    target = Path(a.output or '/private/tmp/seftly-qa-device.png'); target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(adb('exec-out', 'screencap', '-p', binary=True)); print(target)
elif a.action == 'status':
    import urllib.request
    import urllib.error
    def get(path):
        request = urllib.request.Request('http://127.0.0.1:4001'+path, headers={'Authorization':'Bearer '+fixture['parent']['accessToken']})
        try: return json.load(urllib.request.urlopen(request))
        except urllib.error.HTTPError as error:
            if error.code != 401: raise
            refresh = urllib.request.Request('http://127.0.0.1:4001/api/auth/refresh', data=json.dumps({'refreshToken':fixture['parent']['refreshToken']}).encode(), headers={'content-type':'application/json'})
            tokens = json.load(urllib.request.urlopen(refresh)); fixture['parent'].update(tokens)
            Path('/private/tmp/seftly-device-fixture.json').write_text(json.dumps(fixture))
            request.headers['Authorization'] = 'Bearer '+tokens['accessToken']
            return json.load(urllib.request.urlopen(request))
    children = get('/api/children')['children']
    for child in children:
        print('Fixture child:', child['name'], 'device:', (child.get('device') or {}).get('status','unregistered'), 'usage report:', bool(child.get('recentUsage')))
