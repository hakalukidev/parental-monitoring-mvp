"""Validate APK identity/signatures against preserved local keys; never print key passwords."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

root = Path(__file__).resolve().parents[1]
sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home()/'Library/Android/sdk')))
versions = sorted((sdk/'build-tools').iterdir(), key=lambda p: [int(x) for x in re.findall(r'\d+',p.name)])
tools = versions[-1]
java = Path(os.environ.get('JAVA_HOME','/Applications/Android Studio.app/Contents/jbr/Contents/Home'))
results=[]
parentVersion=re.search(r'^version: [^+\n]+\+(\d+)',(root/'parent-app/pubspec.yaml').read_text(),re.M).group(1)
childVersion=re.search(r'versionCode\s*=\s*(\d+)',(root/'child-app/app/build.gradle.kts').read_text()).group(1)
for name,relative,androidRoot,package in [('parent','parent-app/build/app/outputs/flutter-apk/app-release.apk','parent-app/android','com.example.parent_app'),('child','child-app/app/build/outputs/apk/release/app-release.apk','child-app','com.example.childapp')]:
    apk=root/relative
    props={}
    for line in (root/androidRoot/'key.properties').read_text().splitlines():
        if '=' in line and not line.startswith('#'): k,v=line.split('=',1);props[k]=v
    key=(root/androidRoot/'app'/props['storeFile']).resolve()
    original=subprocess.check_output(['git','rev-parse',f'{os.environ.get("SEFTLY_SIGNING_IDENTITY_REFERENCE","73ee98e")}:{key.relative_to(root)}'],cwd=root,text=True).strip()
    unchanged=subprocess.check_output(['git','hash-object',str(key)],cwd=root,text=True).strip()==original
    if not unchanged: raise SystemExit(f'{name}: original signing file changed')
    privateEnv=os.environ.copy(); privateEnv['SEFTLY_CERT_PASS']=props['storePassword'];privateEnv['JAVA_HOME']=str(java)
    cert=subprocess.check_output([str(java/'bin/keytool'),'-exportcert','-keystore',str(key),'-alias',props['keyAlias'],'-storepass:env','SEFTLY_CERT_PASS'],env=privateEnv,stderr=subprocess.PIPE)
    expected=hashlib.sha256(cert).hexdigest()
    verified=subprocess.check_output([str(tools/'apksigner'),'verify','--verbose','--print-certs',str(apk)],env=privateEnv,text=True,stderr=subprocess.PIPE)
    if expected not in verified: raise SystemExit(f'{name}: APK signer does not match the preserved key')
    manifest=subprocess.check_output([str(tools/'aapt2'),'dump','badging',str(apk)],text=True,stderr=subprocess.PIPE)
    expectedVersion=parentVersion if name=='parent' else childVersion
    if f"name='{package}'" not in manifest or f"versionCode='{expectedVersion}'" not in manifest: raise SystemExit(f'{name}: unexpected package/version')
    versionName = re.search(r"package:.*versionName='([^']+)'", manifest).group(1)
    result={'application':name,'path':relative,'package':package,'versionCode':int(expectedVersion),'versionName':versionName,'signed':True,'originalKeyUnchanged':True,'signerSha256':expected,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'sizeBytes':apk.stat().st_size}
    results.append(result);print(f'{name}: package/version/signature verified; original signing identity preserved')
output=root/'release_artifacts';output.mkdir(exist_ok=True)
(output/'artifacts.json').write_text(json.dumps(results,indent=2)+'\n')
