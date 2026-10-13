# Seftly engineering guidance

Use the existing Flutter, Kotlin and TypeScript applications. Preserve production package IDs and signing identities.

- Validate parent-child ownership before every control, read or relay.
- Do not automate Android capture prompts or start camera/microphone capture from a background request.
- Require a visible on-device approval and fresh MediaProjection grant for each session.
- Keep TLS verification enabled. Never log tokens, private records, database URIs or signing credentials.
- Keep keys and runtime environment files outside Git; their removal does not erase historical exposure.
- Report unmeasured usage, stale locations and disconnected devices honestly.
- Keep production retention disabled until an operator has verified backups and the policy.
- Run the checks in the root README before release. Do not overwrite existing APK signatures.

See `docs/ARCHITECTURE.md`, `docs/RELEASE.md` and `docs/IMPLEMENTATION_CHECKLIST.md` for the current contracts, validation and remaining work.
