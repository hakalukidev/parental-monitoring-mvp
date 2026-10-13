"""Build and launch on one explicit device, preferring a sole physical phone."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--mode', choices=['debug', 'release'], default='debug')
parser.add_argument('--serial')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk')))
adb = str(sdk / 'platform-tools/adb')
rows = subprocess.check_output([adb, 'devices'], text=True).splitlines()[1:]
devices = [row.split()[0] for row in rows if len(row.split()) > 1 and row.split()[1] == 'device']
physical = [device for device in devices if not device.startswith('emulator-')]
if args.serial:
    if args.serial not in devices:
        raise SystemExit('The selected device is unavailable or has not authorized USB debugging.')
    serial = args.serial
elif len(physical) == 1:
    serial = physical[0]
elif not physical and len(devices) == 1:
    serial = devices[0]
else:
    raise SystemExit('Choose one connected device with --serial. No app was installed.')
environment = os.environ.copy()
environment.setdefault('JAVA_HOME', '/Applications/Android Studio.app/Contents/jbr/Contents/Home')
environment['ANDROID_HOME'] = str(sdk)
task = 'assembleRelease' if args.mode == 'release' else 'assembleDebug'
subprocess.run(['bash', './gradlew', ':app:' + task], cwd=root/'child-app', env=environment, check=True)
apk = root / f'child-app/app/build/outputs/apk/{args.mode}/app-{args.mode}.apk'
package = 'com.example.childapp' + ('.debug' if args.mode == 'debug' else '')
subprocess.run([adb, '-s', serial, 'install', '-r', str(apk)], check=True)
subprocess.run([adb, '-s', serial, 'shell', 'am', 'start', '-n', package + '/com.example.childapp.ui.MainActivity'], check=True)
print('Seftly Child installed and opened on the selected device.')
