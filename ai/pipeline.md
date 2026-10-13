# Build and release

Follow `docs/RELEASE.md`.

Both production application IDs are preserved. Release keys remain in their original local locations but are ignored by Git. Supply passwords through ignored `key.properties` or secure environment variables. Do not replace keys merely to make a build work.

The parent builds a universal Flutter APK. The child builds a signed standalone universal Android APK; no Play Store workflow is required. Debug variants have separate package suffixes and loopback-only development network configuration.

Never conceal Android recording indicators or automate capture permission dialogs. Review every skipped hardware test and external production dependency before calling a release production-ready.
