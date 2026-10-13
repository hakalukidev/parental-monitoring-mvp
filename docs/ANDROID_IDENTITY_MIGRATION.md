# Android identity continuity

No application-ID or signing-identity migration is performed. These IDs are already installed and changing them would create separate applications with separate data, Android permissions and update paths.

- Parent: `com.example.parent_app`, displayed as Seftly Parent; 1.3.0/code 4.
- Child: `com.example.childapp`, displayed as Seftly Child; 1.3.0/code 4.
- Original signer SHA-256: parent `94275fbc66917577d7074b05b9af46e51b9366944eb34a59f847f898cf89a42b`; child `7cf5f40fef9168356ad702e0258e3fca2cb1008a072416461314d9af691e4221`.

`scripts/verify_release.py` verifies package/version, the APK signer against the original local certificate, and unchanged private keystore bytes against the retained baseline commit `73ee98e`. Private files remain ignored locally; they are never shipped in the backend archive.

Debug IDs use `.debug`; isolated synthetic tests use `.qa`. Neither package replaces a production installation. Production Android installations use `adb install -r` and normal additive SQLite migrations. The Infinix's 1.1/code 2 to 1.2.0/code 3 update succeeded with its first-install timestamp preserved. The signed parent 1.1-to-1.2 emulator update succeeded. These checks establish signing/update compatibility; they do not establish every possible OEM/customer upgrade case.

A future ID migration would require an explicitly planned separate-install/account-link/permission and data-transfer workflow. A future signing change needs an Android-supported lineage/rotation strategy and customer compatibility analysis. Do not silently generate replacement keys.
