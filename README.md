# Parental Screen Monitoring MVP

Consent-based screen sharing between a Parent app and a Child app. The child
must explicitly approve every session (in-app Accept + Android's own
MediaProjection system dialog) before any screen data leaves the device.
No location, mic, camera, SMS, or browsing-history monitoring is implemented.

## Structure

```
parental-monitoring-mvp/
├── backend/       Node.js + Express + TypeScript + MongoDB + Socket.IO
├── parent-app/    Flutter (Material 3)
└── child-app/     Native Android, Kotlin, Jetpack Compose
```

## 1. Backend — deploying to your VPS

### Requirements
- Node.js 18+
- MongoDB (local install or a managed URI, e.g. Atlas)
- nginx (reverse proxy + TLS)
- A domain pointed at your VPS (for `wss://` — required for WebRTC on real devices)

### Steps

```bash
# On the VPS
git clone <your-repo> parental-monitoring-mvp
cd parental-monitoring-mvp/backend
cp .env.example .env
nano .env   # fill in real secrets, MONGO_URI, CORS_ORIGINS, etc.

npm install
npm run build

# Run with pm2 (recommended) so it restarts on crash/reboot
npm install -g pm2
pm2 start dist/server.js --name parental-monitoring-backend
pm2 save
pm2 startup   # follow the printed instructions to enable on boot
```

### nginx reverse proxy (with TLS via certbot)

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo certbot --nginx -d api.yourdomain.com
```

After this, your backend is reachable at `https://api.yourdomain.com` and
Socket.IO at `wss://api.yourdomain.com`.

### Important production notes
- Set strong, unique values for `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
  and `SESSION_TOKEN_SECRET` in `.env` — never reuse the example values.
- Set `CORS_ORIGINS` to your actual app origins.
- **TURN server**: for real-world networks (mobile data, symmetric NATs),
  STUN alone often isn't enough for WebRTC to connect. Run a TURN server
  (e.g. [coturn](https://github.com/coturn/coturn)) on the VPS and set
  `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL` in `.env`. The `/api/config`
  endpoint automatically serves these to both apps.
- The backend never touches raw video — it only relays SDP/ICE signaling
  over Socket.IO. Actual screen frames flow peer-to-peer via WebRTC.
- Presence (`childSockets`/`parentSockets`) is currently in-memory, which is
  fine for a single Node process. If you scale to multiple instances, add
  the `@socket.io/redis-adapter` and move presence into Redis.

## 2. Parent App (Flutter)

```bash
cd parent-app
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://api.yourdomain.com \
  --dart-define=SOCKET_URL=https://api.yourdomain.com
```

Build a release APK/AAB the same way, passing the `--dart-define` flags (or
bake them into `app_config.dart` before building).

## 3. Child App (Android/Kotlin)

Open `child-app/` in Android Studio. Before building, update the backend URLs
in `app/build.gradle.kts`:

```kotlin
buildConfigField("String", "API_BASE_URL", "\"https://api.yourdomain.com\"")
buildConfigField("String", "SOCKET_URL", "\"https://api.yourdomain.com\"")
```

Also remove `android:usesCleartextTraffic="true"` from `AndroidManifest.xml`
once you're pointed at `https://`/`wss://` (it's only needed for local dev
against `http://10.0.2.2`).

Then `Build > Generate Signed Bundle/APK` as usual.

## 4. End-to-end flow to test

1. Register a parent account in the Parent app.
2. Create a child account from the Parent Dashboard.
3. Log into the Child app with that username/password — device registers
   and shows "Connected"; Parent Dashboard shows the child as ONLINE.
4. From the dashboard, tap **Share Screen**.
5. Child app shows the consent dialog ("Your parent wants to view your
   screen... Accept / Reject").
6. On Accept, Android's own MediaProjection system dialog appears — this is
   mandatory and cannot be bypassed.
7. After that's approved, screen capture starts, a persistent "Screen
   sharing active" notification appears on the child device, and the Parent
   app renders the live WebRTC video.
8. Either side can stop the session at any time.

## What's intentionally NOT built

Per the spec: no location tracking, SMS monitoring, camera/microphone
monitoring, app blocking, browsing history capture, or subscriptions. Adding
any of these — especially covert versions — is out of scope for this project
and won't be added even on request, since covert monitoring of a minor's
camera/mic/location crosses into surveillance that bypasses the child's
knowledge and consent.
# parental-monitoring-mvp
