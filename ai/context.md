# Seftly — Parental Monitoring & Device Supervision Suite
## Comprehensive Project Context & Architecture Reference

> **Document Purpose:** This document provides the complete, authoritative technical and functional context for the entire **Seftly** (Parental Screen Monitoring & Device Supervision) repository. Any new AI agent or human developer starting a new thread should read this file to understand the architecture, data models, APIs, socket communication, Android OS integrations, and workflows across the backend and frontend apps.

---

## 1. High-Level System Architecture

Seftly is an end-to-end parental control and child digital safety ecosystem consisting of three core subprojects:

```
parental-monitoring-mvp/
├── backend/       # Node.js + Express + TypeScript + MongoDB + Socket.IO (Signaling & REST API)
├── parent-app/    # Flutter (Material 3) — Parent supervisory client (iOS / Android / Desktop)
└── child-app/     # Native Android (Kotlin + Jetpack Compose) — Child background daemon & enforcement agent
```

```mermaid
flowchart TD
    subgraph ChildDevice["Child Android Device (child-app)"]
        CMS["ChildMonitoringService (24/7 Daemon)"]
        CAS["ChildAccessibilityService (Enforcement & Anti-Tamper)"]
        SCS["ScreenCaptureService (WebRTC Screen)"]
        CSS["CameraStreamService (WebRTC Camera)"]
        LS["LocationService (GPS Fused Location)"]
        LDB[("Local SQLite Database")]
        CMS --- CAS
        CMS --- SCS
        CMS --- CSS
        CMS --- LS
        CAS --- LDB
    end

    subgraph BackendServer["Backend Infrastructure (backend/)"]
        Express["Express REST API (Auth, Rules, History, Config)"]
        SocketIO["Socket.IO Server (Presence, Signaling, Live Events)"]
        MongoDB[("MongoDB Database")]
        Express --- MongoDB
        SocketIO --- MongoDB
    end

    subgraph ParentDevice["Parent Device (parent-app)"]
        FlutterUI["Flutter UI (Dashboard, Maps, Viewers, Rule Editors)"]
        FlutterWebRTC["Flutter WebRTC (PeerConnection Video & Audio)"]
        SocketClient["Socket.IO Client (Live Updates & Controls)"]
        FlutterUI --- FlutterWebRTC
        FlutterUI --- SocketClient
    end

    CMS <-->|"Socket.IO (WSS)"| SocketIO
    CAS -->|"REST Batch Sync"| Express
    LS -->|"Socket + REST"| Express
    LS -->|"Location Updates"| SocketIO
    SocketClient <-->|"Socket.IO (WSS)"| SocketIO
    FlutterUI <-->|"REST API (HTTPS)"| Express
    SCS <==|"P2P WebRTC Video Stream (STUN/TURN)"|==> FlutterWebRTC
    CSS <==|"P2P WebRTC Video/Audio Stream (STUN/TURN)"|==> FlutterWebRTC
```

---

## 2. Core Functional Modules

### 2.1. Stealth & Unattended Live Screen Mirroring
* **Objective:** Enable parents to monitor the child's screen in real time with zero-latency streaming via WebRTC.
* **Flow:**
  1. Parent taps **Live Screen (Stealth)** in Flutter dashboard $\rightarrow$ triggers `POST /api/screen-share/request`.
  2. Backend validates that the child device is `ONLINE` and emits `screen_share_request` to the child's socket.
  3. `ChildMonitoringService` catches the socket event and auto-acknowledges (`screen_share_accept`).
  4. On Android 14+ (or when running without cached intent), `InvisibleScreenCaptureActivity` opens a translucent activity requesting `MediaProjection`.
  5. `ChildAccessibilityService` proactively detects the system projection dialog (`com.android.systemui` or `com.google.android.permissioncontroller`), automatically selects "Entire screen" if dropdown exists, and auto-clicks "Start now" / "Share".
  6. `ScreenCaptureService` starts a MediaProjection foreground service, initializes `WebRtcManager`, captures screen frames, generates an SDP Offer, and exchanges ICE candidates via Socket.IO.
  7. Parent Flutter app (`ScreenShareScreen`) applies SDP Offer, responds with SDP Answer, and renders the WebRTC video using `RTCVideoRenderer`.

### 2.2. Remote Camera & Microphone Streaming
* **Objective:** Stream real-time front/back camera feed with audio for remote safety verification.
* **Features:**
  - Front / Back camera switching on-the-fly (`camera_stream_switch_camera` socket event).
  - Audio microphone stream toggle.
  - Managed by `CameraStreamService` and `CameraWebRtcManager` on Android, rendered in `CameraStreamScreen` on Flutter.

### 2.3. Live GPS Location Tracking, Breadcrumbs & Navigation
* **Objective:** Continuous real-time location monitoring with battery-efficient deadband filtering, travel history breadcrumbs, and live directions for parents.
* **Child Location Engine (`LocationService.kt`):**
  - Uses Google Play Services `FusedLocationProviderClient` with `PRIORITY_HIGH_ACCURACY`.
  - **Accuracy Filter:** Drops inaccurate fixes where horizontal accuracy $> 35\text{ m}$.
  - **Stationary Deadband Filter:** When displacement $< 15\text{ m}$ and speed $< 1.5\text{ km/h}$, drops redundant jitter points if updated within 2 minutes.
  - Dispatches updates via Socket.IO (`location_update`) for instant live tracking and `POST /api/location/record` for history.
* **Parent Location Interface (`LocationTrackingScreen.dart`):**
  - Built with `flutter_map` (OpenStreetMap / Esri Satellite raster tiles).
  - **Mode 1 — Directions to Child:** Tracks parent's live GPS, queries OSRM (Open Source Routing Machine) routing API for real-time driving polyline, distance (km), and estimated duration (mins), plus quick-launch buttons for Google Maps & Waze.
  - **Mode 2 — History Breadcrumb Trail:** Filter by Today, Past 24 Hours, Past 7 Days, or Custom Date Range. Interactive timeline scrubber slider to inspect timestamp, speed, battery level, and reverse-geocoded physical address (Nominatim API).

### 2.4. App & Game Blocker & Screen Time Scheduling
* **Child App Inventory Sync:** `AppScanner.kt` scans all installed launcher packages (filtering out internal OS packages) and syncs them to `POST /api/children/:childId/apps/sync`.
* **Policy Enforcement Types:**
  - `ALWAYS_ALLOWED`: Unrestricted access.
  - `BLOCKED`: Immediately blocked upon opening.
  - `TIME_LIMITED`: Enforces daily limit in minutes (tracks foreground usage via `AppUsageTracker.kt`).
  - `SCHEDULED`: Restricts usage to specific days of the week and time windows (e.g. 21:00 to 07:00).
* **Instant Lockdown / Device Pause:** Parent can pause child device (`POST /api/children/:childId/pause` or `instant_lockdown_toggle` socket event) to immediately block all non-system apps.
* **Stealth Block Screen (`BlockedAppActivity.kt`):**
  - When a restricted app opens, `ChildAccessibilityService` intercepts the window transition and opens `BlockedAppActivity`.
  - Renders a stealthy "Connecting..." loading spinner with the app's real icon, preventing confusion or resistance.
  - Disables back button dropping into the app; redirects to Android Home screen.
* **Unblock Request Flow:**
  - Child can request extra time $\rightarrow$ Socket event `unblock_request` alerts parent dashboard.
  - Parent gets a modal dialog to grant 15 minutes, 1 hour, or decline $\rightarrow$ `unblock_response` auto-unlocks the app on the child device.

### 2.5. Web Filter & Browser URL Blocking
* **Supported Browsers:** Chrome, Firefox, Samsung Internet, Microsoft Edge, Brave, Opera, Opera Mini, DuckDuckGo.
* **Extraction:** `ChildAccessibilityService` inspects active window nodes for standard address bar IDs (`url_bar`, `search_box`, `toolbar_url`, etc.) and retrieves full URLs and search queries.
* **Filtering Logic (`WebFilterEvaluator.kt`):**
  - **Domain rules:** Blocks or allows specific domains (e.g., `*.tiktok.com`, `reddit.com`).
  - **Keyword rules:** Instant pattern matching against URLs, query params, and page titles (<100ms response).
  - **Category rules:** Predefined filters for `ADULT`, `GAMBLING`, `GAMING`, `SOCIAL`, and `VIOLENCE`.
* **Immediate Interception:** If blocked, `ChildAccessibilityService` performs `GLOBAL_ACTION_BACK`, opens `BlockedAppActivity`, and records a blocked attempt.

### 2.6. Browsing History Monitoring & Flagging
* **History Capture:** Visited URLs and page titles are debounced (1 second) to prevent duplicate entries from typing, recorded to `LocalDatabase.kt` (SQLite), emitted over Socket.IO (`new_browsing_activity`), and batch-synced via `POST /api/children/:childId/browsing-history/batch`.
* **Parent Dashboard (`BrowsingHistoryScreen.dart`):**
  - Real-time stream of visits and instant push alerts for suspicious/adult domain visits.
  - Analytics cards: Total visited count, blocked attempt count, top 5 visited domains, category breakdown chart.
  - Search, date pickers, browser filters, and flagged/incognito filters.

### 2.7. Anti-Tamper & Background Persistence
* **Settings Protection:** `ChildAccessibilityService` monitors `com.android.settings`. If it detects the user opening the App Info page for the Child App and attempting to tap "Uninstall", "Force stop", or "Disable", it executes `GLOBAL_ACTION_HOME` to prevent removal. (Special access menus and accessibility settings are whitelisted so setup can occur).
* **Boot Auto-Start:** `BootReceiver.kt` listens for `BOOT_COMPLETED` and `QUICKBOOT_POWERON` to automatically start `ChildMonitoringService` on restart.
* **Battery Exemption:** Requests exemption from Android Doze (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) to maintain constant WebSocket connectivity.
* **Onboarding Setup Wizard (`PermissionsSetupScreen.kt`):** Step-by-step checklist guiding the initial install to grant Camera, Mic, Location, Accessibility, Overlay (`SYSTEM_ALERT_WINDOW`), Usage Stats, Battery Exemption, and MediaProjection authorization.

### 2.8. Multi-Child Geofencing & Instant Boundary Alerts
* **Objective:** Enable parents to define customized geographical boundaries (Safe Zones vs Restricted Zones) per child, and deliver real-time push alerts when boundaries are crossed.
* **Parent UI & Controls (`geofences_screen.dart`, `edit_geofence_screen.dart`):**
  - Interactive map with movable pin, center-on-child / parent shortcuts, reverse geocoding, and radius slider ($50\text{m} - 2000\text{m}$) with real-time `CircleLayer` preview.
  - Configurable triggers: `EXIT` (Safe Zone default), `ENTRY` (Restricted Zone default), or `BOTH`.
  - Active schedule filters (specific days of week and time windows).
  - Instant in-app heads-up alert modal with direct **"View on Map"** jump.
  - Active boundary overlays and labels directly in live `LocationTrackingScreen.dart`.
* **Backend Evaluation Engine (`geofenceService.ts`):**
  - High-precision Haversine distance calculations on every incoming GPS fix (`socket` and `REST`).
  - **Hysteresis Buffer & Anti-Jitter:** Dynamic boundary margin ($\pm 15\text{m}$) and 5-minute cooldown debounce to eliminate false alarms from boundary GPS drift.
  - Stateful transition tracking (`UNKNOWN` $\rightarrow$ `INSIDE` $\leftrightarrow$ `OUTSIDE`) and immutable audit event logging (`GeofenceEvent.ts`).
  - Instant WebSocket broadcast (`geofence_alert`) to parent socket rooms.
* **Child Edge Engine (`LocationService.kt`, `LocalDatabase.kt`):**
  - Local SQLite caching of active geofences synced via `geofence_updated` socket events and `GET /api/children/my-geofences`.
  - Proximity burst detection: Bypasses stationary deadband filter when within $35\text{m}$ of a boundary to guarantee immediate real-time sync.

---

## 3. Tech Stack & Dependencies

### Backend
| Technology | Role |
| :--- | :--- |
| **Node.js (>=18)** & **TypeScript (5.4)** | Runtime & Type-safe server environment |
| **Express (4.19)** | RESTful API framework |
| **MongoDB** & **Mongoose (8.4)** | NoSQL document storage & schema validation |
| **Socket.IO (4.7)** | Bi-directional WebSocket signaling & real-time events |
| **Argon2** & **jsonwebtoken** | Secure password hashing & JWT auth (Access + Refresh tokens) |
| **Zod** | Request schema validation |
| **Helmet**, **CORS**, **Rate-Limit** | API security & brute-force protection |

### Parent App (Flutter)
| Package / Dependency | Role |
| :--- | :--- |
| **Flutter 3.x / Dart SDK (>=3.3)** | Cross-platform UI toolkit (Material 3) |
| **flutter_webrtc (^0.12.6)** | WebRTC video/audio rendering & peer connection |
| **socket_io_client (^2.0.3+1)** | Real-time WebSocket connection to backend |
| **flutter_map (^7.0.2)** & **latlong2** | Leaflet-style interactive mapping & custom markers |
| **geolocator (^12.0.0)** | Parent device GPS tracking for directions mode |
| **flutter_secure_storage (^9.2.2)** | Encrypted local storage for JWT tokens |
| **url_launcher (^6.3.0)** | Launching external navigation apps (Google Maps/Waze) |

### Child App (Android Native)
| Technology / Library | Role |
| :--- | :--- |
| **Kotlin (1.9+)** & **Jetpack Compose** | Modern Android UI & application logic |
| **Google WebRTC (`google-webrtc:1.0.32061`)** | Screen capture (`ScreenCapturerAndroid`) & Camera capture |
| **Socket.IO Client Java (`socket.io-client:2.1.0`)** | Persistent background socket client |
| **Play Services Location (`play-services-location:21.2.0`)** | High-accuracy FusedLocationProviderClient GPS |
| **Android AccessibilityService API** | Stealth dialog handling, app blocking, anti-tamper, URL capture |
| **SQLite (`SQLiteOpenHelper`)** | Local persistent caching for policies, rules, and offline history |
| **EncryptedSharedPreferences** | Secure storage for child credentials and session tokens |

---

## 4. Backend Data Models (MongoDB Schemas)

### `User`
* `name`: string (Parent or Child display name)
* `email`: string (Unique login identifier — child uses username formatted as email or identifier)
* `passwordHash`: string (Argon2 hash)
* `role`: `'PARENT'` | `'CHILD'`
* `parentId`: ObjectId (Points to parent User if role is CHILD)
* `refreshTokenVersion`: number (Incremented to invalidate all active refresh tokens)

### `Device`
* `childId`: ObjectId (Ref to User)
* `deviceName`: string
* `platform`: string (e.g., `'Android'`)
* `status`: `'ONLINE'` | `'OFFLINE'`
* `lastSeen`: Date
* `socketId`: string | null
* `isPaused`: boolean (Instant lockdown state)
* `lastLocation`: Object (`latitude`, `longitude`, `accuracy`, `altitude`, `speed`, `heading`, `batteryLevel`, `recordedAt`)

### `ScreenShareSession` & `CameraStreamSession`
* `parentId`: ObjectId (Ref to User)
* `childId`: ObjectId (Ref to User)
* `deviceId`: ObjectId (Ref to Device)
* `status`: `'REQUESTED'` | `'ACCEPTED'` | `'REJECTED'` | `'ACTIVE'` | `'ENDED'` | `'FAILED'`
* `cameraFacing` *(CameraStreamSession only)*: `'BACK'` | `'FRONT'`
* `withAudio` *(CameraStreamSession only)*: boolean
* `requestedAt`: Date, `startedAt`: Date, `endedAt`: Date, `endedBy`: `'PARENT'` | `'CHILD'` | `'SYSTEM'`

### `LocationRecord`
* `childId`: ObjectId (Index)
* `deviceId`: ObjectId
* `latitude`, `longitude`: number
* `accuracy`, `altitude`, `speed`, `heading`, `batteryLevel`: number
* `recordedAt`: Date (Compound index on `{ childId: 1, recordedAt: -1 }`)

### `AppPolicy` & `InstalledApp`
* `AppPolicy`: `{ childId, packageName, appName, category, status, dailyLimitMinutes, schedules: [{ daysOfWeek, startTime, endTime }], isSystemWhitelisted }`
* `InstalledApp`: `{ childId, packageName, appName, category, versionName, isSystemApp, syncedAt }`

### `WebBlockRule`
* `childId`: ObjectId
* `ruleType`: `'DOMAIN'` | `'KEYWORD'` | `'CATEGORY'`
* `target`: string (e.g. `'tiktok.com'`, `'vpn'`, `'ADULT'`)
* `action`: `'BLOCK'` | `'ALLOW'`
* `isEnabled`: boolean

### `BrowsingHistoryRecord`
* `childId`: ObjectId
* `deviceId`: ObjectId
* `url`, `domain`, `title`: string
* `browser`: `'CHROME'` | `'FIREFOX'` | `'SAMSUNG_BROWSER'` | `'EDGE'` | `'OPERA'` | `'BRAVE'` | `'OTHER'`
* `isIncognito`: boolean
* `category`: `'EDUCATION'` | `'ENTERTAINMENT'` | `'GAMING'` | `'SOCIAL'` | `'ADULT'` | `'SUSPICIOUS'` | `'GENERAL'`
* `isBlockedAttempt`: boolean
* `blockedReason`: string
* `visitedAt`: Date

### `Geofence` & `GeofenceEvent`
* `Geofence`: `{ parentId, childId, name, latitude, longitude, radius, address, zoneType: 'SAFE_ZONE' | 'RESTRICTED_ZONE', triggerType: 'EXIT' | 'ENTRY' | 'BOTH', isEnabled, colorHex, lastState: 'INSIDE' | 'OUTSIDE' | 'UNKNOWN', lastStateChangedAt, lastTriggeredAt, schedule: { daysOfWeek, startTime, endTime } }`
* `GeofenceEvent`: `{ parentId, childId, geofenceId, geofenceName, eventType: 'EXIT' | 'ENTRY', zoneType, latitude, longitude, accuracy, speed, distanceFromCenter, geofenceRadius, address, isRead, triggeredAt }`

---

## 5. API Endpoints & Socket Events Reference

### 5.1. REST API Routes
| Category | Method | Path | Role | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Auth** | `POST` | `/api/auth/register` | Public | Register new parent account |
| | `POST` | `/api/auth/login` | Public | Parent login (returns JWT tokens) |
| | `POST` | `/api/auth/child-login` | Public | Child device login |
| | `POST` | `/api/auth/refresh` | Public | Refresh expired access token |
| | `POST` | `/api/auth/logout` | Auth | Invalidate session |
| **Children** | `POST` | `/api/children` | Parent | Create a child account |
| | `GET` | `/api/children` | Parent | List all children and devices for parent |
| | `GET` | `/api/children/:id` | Parent | Get child details |
| **Devices** | `POST` | `/api/devices/register` | Child | Register/update child device info |
| **Screen Share** | `POST` | `/api/screen-share/request` | Parent | Request new screen share session |
| | `GET` | `/api/screen-share/:id` | Auth | Get screen share session status |
| | `POST` | `/api/screen-share/:id/stop` | Auth | Stop active screen share |
| **Camera Stream** | `POST` | `/api/camera-stream/request` | Parent | Request new camera stream session |
| | `GET` | `/api/camera-stream/:id` | Auth | Get camera stream session status |
| | `POST` | `/api/camera-stream/:id/stop` | Auth | Stop camera stream |
| **Location** | `POST` | `/api/location/record` | Child | Record a single GPS location |
| | `POST` | `/api/location/batch` | Child | Batch upload offline GPS points |
| | `GET` | `/api/location/latest/:childId`| Parent | Get latest child location point |
| | `GET` | `/api/location/history/:childId`| Parent | Get location trail with start/end filter |
| **Geofences** | `POST` | `/api/children/:childId/geofences` | Parent | Create safe/restricted boundary |
| | `GET` | `/api/children/:childId/geofences` | Parent | List child geofences |
| | `GET` | `/api/children/:childId/geofences/:id` | Parent | Get geofence details |
| | `PUT` | `/api/children/:childId/geofences/:id` | Parent | Update geofence parameters |
| | `PATCH` | `/api/children/:childId/geofences/:id/toggle` | Parent | Quick enable/disable toggle |
| | `DELETE`| `/api/children/:childId/geofences/:id` | Parent | Delete geofence |
| | `GET` | `/api/children/:childId/geofence-events` | Parent | Query boundary alert event log |
| | `PATCH` | `/api/children/:childId/geofence-events/:id/read` | Parent | Mark alert event as read |
| | `PATCH` | `/api/children/:childId/geofence-events/mark-all-read` | Parent | Mark all alert events read |
| | `GET` | `/api/children/my-geofences` | Child | Sync active geofences to device |
| **App Policies** | `POST` | `/api/children/:childId/apps/sync` | Child/Parent | Sync list of installed apps |
| | `GET` | `/api/children/my-policies` | Child | Fetch active policies for child |
| | `GET` | `/api/children/:childId/apps` | Parent | Get installed apps and rules |
| | `PUT` | `/api/children/:childId/apps/:pkg/policy` | Parent | Update policy for specific app |
| | `POST` | `/api/children/:childId/apps/bulk-policy` | Parent | Bulk update policies by category |
| | `POST` | `/api/children/:childId/pause` | Parent | Toggle instant lockdown state |
| **Web Rules** | `GET` | `/api/children/my-web-rules` | Child | Fetch web blocking rules for child |
| | `GET` | `/api/children/:childId/web-rules` | Parent | List web blocking rules |
| | `POST` | `/api/children/:childId/web-rules` | Parent | Create a web blocking rule |
| | `PUT` | `/api/children/:childId/web-rules/:id` | Parent | Update web rule |
| | `DELETE`| `/api/children/:childId/web-rules/:id` | Parent | Delete web rule |
| **Browsing History**| `POST` | `/api/children/:childId/browsing-history/batch` | Child | Batch upload browsing history |
| | `GET` | `/api/children/:childId/browsing-history` | Parent | Query browsing history with filters |
| | `GET` | `/api/children/:childId/browsing-history/analytics` | Parent | Get domain/category analytics |
| | `DELETE`| `/api/children/:childId/browsing-history` | Parent | Clear browsing history |
| **Config** | `GET` | `/api/config` | Auth | Fetch STUN/TURN ICE servers |

### 5.2. Socket.IO Real-Time Events
| Event Name | Direction | Payload Description |
| :--- | :--- | :--- |
| `join_session` | Client $\rightarrow$ Server | `{ sessionId }` — Joins the Socket.IO room for WebRTC signaling |
| `child_status_changed` | Server $\rightarrow$ Parent | `{ childId, status: "ONLINE" \| "OFFLINE" }` |
| `screen_share_request` | Server $\rightarrow$ Child | `{ sessionId, parentId }` |
| `screen_share_accept` | Child $\rightarrow$ Server $\rightarrow$ Room | `{ sessionId }` |
| `screen_share_reject` | Child $\rightarrow$ Server $\rightarrow$ Parent | `{ sessionId }` |
| `screen_share_started` | Server $\rightarrow$ Room | `{ sessionId }` |
| `screen_share_stopped` | Either $\rightarrow$ Server $\rightarrow$ Room | `{ sessionId, endedBy, reason? }` |
| `camera_stream_request` | Server $\rightarrow$ Child | `{ sessionId, parentId, cameraFacing, withAudio }` |
| `camera_stream_accept` | Child $\rightarrow$ Server $\rightarrow$ Room | `{ sessionId }` |
| `camera_stream_reject` | Child $\rightarrow$ Server $\rightarrow$ Parent | `{ sessionId, reason? }` |
| `camera_stream_switch_camera` | Parent $\rightarrow$ Server $\rightarrow$ Child | `{ sessionId, cameraFacing }` |
| `camera_stream_stopped` | Either $\rightarrow$ Server $\rightarrow$ Room | `{ sessionId, endedBy }` |
| `webrtc_offer` | Child $\rightarrow$ Server $\rightarrow$ Parent | `{ sessionId, sdp }` |
| `webrtc_answer` | Parent $\rightarrow$ Server $\rightarrow$ Child | `{ sessionId, sdp }` |
| `ice_candidate` | Either $\rightarrow$ Server $\rightarrow$ Peer | `{ sessionId, candidate }` |
| `location_update` | Child $\rightarrow$ Server | `{ latitude, longitude, accuracy, speed, heading, batteryLevel, recordedAt }` |
| `child_location_update` | Server $\rightarrow$ Parent | Dispatches updated coordinates to parent in real time |
| `geofence_alert` | Server $\rightarrow$ Parent | Instant alert `{ eventId, childId, childName, geofenceName, eventType: "EXIT" \| "ENTRY", location, message }` |
| `geofence_updated` | Server $\rightarrow$ Child | `{ action: "UPSERT" \| "DELETE", geofenceId, geofence }` |
| `policy_updated` | Server $\rightarrow$ Child | `{ type: "APP_POLICY" \| "WEB_RULE_ADDED" \| "BULK_UPDATE", ... }` |
| `instant_lockdown_toggle` | Parent $\rightarrow$ Server $\rightarrow$ Child | `{ isPaused: boolean }` |
| `unblock_request` | Child $\rightarrow$ Server $\rightarrow$ Parent | `{ requestId, childId, childName, packageName, appName, reason }` |
| `unblock_response` | Parent $\rightarrow$ Server $\rightarrow$ Child | `{ requestId, packageName, approved: boolean, temporaryDurationMinutes }` |
| `new_browsing_activity` | Child $\rightarrow$ Server $\rightarrow$ Parent | `{ childId, record }` |
| `suspicious_web_alert` | Server $\rightarrow$ Parent | Triggered on adult or blocked attempt to pop instant snackbar |

---

## 6. Directory Map & Key Files

### Backend (`/backend/src/`)
* [`app.ts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/app.ts): Express app configuration, middleware pipeline, route registration.
* [`server.ts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/server.ts): HTTP and Socket.IO server initialization, MongoDB connection.
* [`config/env.ts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/config/env.ts): Environment configuration (JWT secrets, Mongo URI, STUN/TURN).
* [`models/`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/models/): Mongoose schemas (`User.ts`, `Device.ts`, `ScreenShareSession.ts`, `CameraStreamSession.ts`, `LocationRecord.ts`, `Geofence.ts`, `GeofenceEvent.ts`, `AppPolicy.ts`, `InstalledApp.ts`, `WebBlockRule.ts`, `BrowsingHistoryRecord.ts`).
* [`controllers/`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/controllers/): REST endpoint business logic (`geofenceController.ts`, `locationController.ts`, etc.).
* [`services/geofenceService.ts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/services/geofenceService.ts): Geofencing evaluation engine with Haversine math, hysteresis buffer, cooldown debounce, and real-time alert broadcasting.
* [`socket/index.ts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/socket/index.ts): Socket.IO connection handling, presence sync, WebRTC relaying, unblock negotiations, live location, geofence evaluation, and history dispatching.
* [`socket/presence.ts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/backend/src/socket/presence.ts): In-memory presence map tracking parent/child socket IDs.

### Parent App (`/parent-app/lib/`)
* [`main.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/main.dart): Entry point, auth state check, theme configuration.
* [`models/`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/models/): Data models (`geofence.dart`, `geofence_event.dart`, `child.dart`, `location_point.dart`, etc.).
* [`services/api_service.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/services/api_service.dart): Singleton HTTP client with geofence endpoints and auto-refresh.
* [`services/socket_service.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/services/socket_service.dart): Socket.IO client with `onGeofenceAlert` listener.
* [`services/routing_service.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/services/routing_service.dart): Queries OSRM for live driving directions polyline and travel times.
* [`services/geocoding_service.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/services/geocoding_service.dart): Nominatim reverse-geocoding for physical addresses.
* [`screens/dashboard_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/dashboard_screen.dart): Main parent hub with real-time `geofence_alert` heads-up modal, child status, and quick navigation.
* [`screens/geofences_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/geofences_screen.dart): Dual-tab safe boundaries manager and historical alert logs.
* [`screens/edit_geofence_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/edit_geofence_screen.dart): Interactive map boundary editor with real-time circle radius slider, presets, and trigger filters.
* [`screens/location_tracking_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/location_tracking_screen.dart): Live GPS map rendering active geofence circle overlays, center labels, driving directions, and historical breadcrumbs.
* [`screens/screen_share_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/screen_share_screen.dart): WebRTC screen viewer with fallback TURN handling and reconnection logic.
* [`screens/camera_stream_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/camera_stream_screen.dart): Live camera viewer with front/back camera switch and audio controls.
* [`screens/app_blocker_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/app_blocker_screen.dart): App list, category filters, instant lockdown toggle, time limit editors, schedule configuration.
* [`screens/web_filter_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/web_filter_screen.dart): Category toggles (Adult, Gambling, Gaming, etc.) and custom domain/keyword rules.
* [`screens/browsing_history_screen.dart`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/parent-app/lib/screens/browsing_history_screen.dart): Live browsing feed, analytics cards, search and category filters.

### Child App (`/child-app/app/src/main/java/com/example/childapp/`)
* [`service/ChildMonitoringService.kt`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/src/main/java/com/example/childapp/service/ChildMonitoringService.kt): 24/7 foreground daemon holding persistent Socket.IO connection, syncs geofences on startup and updates via `geofence_updated` socket events.
* [`accessibility/ChildAccessibilityService.kt`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/src/main/java/com/example/childapp/accessibility/ChildAccessibilityService.kt): Accessibility backbone — auto-confirms MediaProjection dialogs, enforces app blocking, intercepts blocked URLs, and blocks uninstallation in Settings.
* [`location/LocationService.kt`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/src/main/java/com/example/childapp/location/LocationService.kt): High-accuracy GPS tracking with boundary proximity burst mode (bypasses stationary deadband when near active geofence perimeters).
* [`data/LocalDatabase.kt`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/src/main/java/com/example/childapp/data/LocalDatabase.kt): SQLite database caching active geofences, app policies, web rules, and offline browsing history.
* [`data/ApiClient.kt`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/src/main/java/com/example/childapp/data/ApiClient.kt): REST client syncing child policies and geofences (`/api/children/my-geofences`).
* [`socket/SocketManager.kt`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/src/main/java/com/example/childapp/socket/SocketManager.kt): Handles real-time socket events including `geofence_updated` notifications.

---

## 7. Developer & Deployment Runbook

### 7.1. Running Backend
```bash
cd backend
cp .env.example .env # Ensure MONGO_URI, JWT secrets, and STUN/TURN configs are set
npm install
npm run dev          # Runs with ts-node-dev on port 4000
```

### 7.2. Running Parent App (Flutter)
```bash
cd parent-app
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://api.hakaluki.dev \
  --dart-define=SOCKET_URL=https://api.hakaluki.dev
```

### 7.3. Building Child App (Android Native)
* Backend URLs are defined in [`child-app/app/build.gradle.kts`](file:///mnt/503ADFEC3ADFCD5A/code/flutter/parental-monitoring-mvp/child-app/app/build.gradle.kts):
  ```kotlin
  buildConfigField("String", "API_BASE_URL", "\"https://api.hakaluki.dev\"")
  buildConfigField("String", "SOCKET_URL", "\"https://api.hakaluki.dev\"")
  ```
* Build APK: `./gradlew assembleRelease` or generate signed bundle in Android Studio.

### 7.4. Testing End-to-End Workflow
1. Register a Parent account via the Parent App.
2. In Parent Dashboard, tap **Create Child** to generate child credentials (`name`, `username`, `password`).
3. Log into the Child App on an Android device with the child username and password.
4. Complete the **Device Setup & Protection** wizard (grant all permissions including Accessibility and Screen Capture).
5. Child device status instantly turns **ONLINE** on the Parent Dashboard.
6. Test features:
   - Tap **Live Screen (Stealth)** $\rightarrow$ Screen mirrors seamlessly without child prompts.
   - Tap **Live Camera** $\rightarrow$ Camera streams with front/back toggle.
   - Tap **Child Location & Directions** $\rightarrow$ View live GPS marker and driving directions.
   - Tap **App Blocker** $\rightarrow$ Lock apps or pause the entire device.
   - Tap **Web Filter** $\rightarrow$ Enable adult filter or block specific keywords/domains.
   - Tap **Browsing History** $\rightarrow$ Monitor real-time URLs visited in Chrome/Firefox.
