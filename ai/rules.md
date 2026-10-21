# AI Development Rules

## 1. Do Not Automatically Run Apps or Backend After Modifications
- **Never automatically run, install, or launch the backend, child-app, or parent-app after making code changes.**
  - Do NOT run commands like:
    - `adb install ...`
    - `adb shell am start ...`
    - `waydroid app launch ...`
    - `flutter run ...`
    - `./run.sh` / `./gradlew installDebug`
    - `npm run dev` / `npm start`
- **User Manual Execution**:
  - After any code modification, the user will manually run, launch, and test the backend, child-app APK, and parent-app APK themselves.
- **Allowed Verification**:
  - Offline static checks (such as `flutter analyze`, `tsc -p tsconfig.json`, or `./gradlew compileDebugKotlin` to verify there are no compilation/syntax errors) are permitted when relevant, but do NOT execute or deploy the running software.
