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

## 2. Follow Centralized Color Theme for All UI Modifications
- **Strictly adhere to the centralized color theme when modifying or building UI in both `parent-app` and `child-app`:**
  - **Single Source of Truth**: Like Next.js `index.css`, all theme color variables are centralized. Never introduce arbitrary or hardcoded colors (`Color(0x...)`, random `Colors.blue`, `Colors.green`, etc.) directly inside UI components or screens.
  - **In `parent-app` (Flutter)**:
    - Use `AppColors` from `lib/theme/app_colors.dart` (e.g., `AppColors.primary`, `AppColors.card`, `AppColors.background`, `AppColors.accent`, `AppColors.destructive`) or `Theme.of(context)`.
    - If a color needs adjustment, change it only in `parent-app/lib/theme/app_colors.dart`.
  - **In `child-app` (Android Jetpack Compose)**:
    - Use `MaterialTheme.colorScheme`, `AppTheme.palette`, or `AppColors.Current` from `com.example.childapp.ui.theme`.
    - If a color needs adjustment, change it only in `child-app/app/src/main/java/com/example/childapp/ui/theme/Color.kt`.
