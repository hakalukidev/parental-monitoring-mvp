# Current project context

Seftly has a Flutter parent client, a Kotlin/Compose child client and a Node/Express/Mongoose backend. This is an existing application with preserved production identifiers.

The parent has 13 screens. The child uses one monitoring connection, explicit per-session consent activities, independent media-service sockets and persistent offline policy/history queues. Signaling is restricted to authenticated participants and their current sessions.

The previous descriptions of automatic capture approval, hidden monitoring and inferred screen-off metrics are retired. They must not be restored.

The authoritative current documentation is in the root README and `docs/`. Production deployment must wait for validated host access, backups, rollback references and a coordinated client/website rollout.
