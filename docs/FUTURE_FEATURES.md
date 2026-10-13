# Secondary milestone features: feasibility and release gates

Reviewed on 2026-10-13. These are proposed designs, not implemented capabilities.

## Calls and SMS

The manifest does not declare call-log or SMS collection, and there is no implemented ingestion/viewer flow. Android distinguishes runtime permission from eligibility for sensitive permission groups. For Google Play distribution, default-handler requirements or a documented exception apply; private APK distribution is not proof of supported access on every OS. A real default SMS/phone implementation would need the actual handler functionality and user consent, not a permission-only shortcut. See [Android's default-handler guidance](https://developer.android.com/guide/topics/permissions/default-handlers).

Choose a supported, explicitly authorized integration and distribution model before implementation. Use child-shared summaries or an authorized provider's API where suitable. Review applicable jurisdiction and guardianship requirements with qualified counsel; no legal-compliance claim is made here. Do not scrape private messages using Accessibility, intercept credentials, or bypass another app's protections.

## Social content

No platform-authorized social-content connector exists in this repository. Ordinary app sandboxing prevents unrestricted access to another app's private data; Android recommends narrowly controlled cross-app data sharing. See [Android's security guidance](https://developer.android.com/privacy-and-security/security-tips). Support explicit sharing by the child or a provider-supported account authorization/export. Notification text is incomplete, can be redacted, and must never be described as full social-message access.

## App notifications

Android provides [NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService), with a system-bound service and lifecycle callbacks. A future implementation should explain notification access separately, let the guardian and child choose an app allowlist, and show an always-available disable control. Exclude sensitive authentication/payment/password notifications and Seftly's own notices. Default to package, time and notification count; collecting content needs a separate purpose and explicit scope. Apply ownership checks, bounded offline queues, configurable retention and deletion/export. Honor system redaction and missing access. Verify permission revocation, listener disconnect/rebind, duplicates, lock-screen/work-profile restrictions and OEM behavior before claiming support.

## Sound Around Child

Optional microphone audio in an approved camera session is implemented, but an audio-only Sound Around flow is absent. A future flow needs its own visible child approval, foreground microphone service, live indicator, Stop control, timeout, participant authorization and no recording by default. It must not start remotely without on-device approval.

## Image/video safety detection

There is no inference model, labeled evaluation dataset or measured accuracy. General-purpose image labels do not establish inappropriate-content detection. [ML Kit supports custom TensorFlow Lite classification models](https://developers.google.com/ml-kit/custom-models); that is a possible integration mechanism, not a validated safety model.

Evaluate a licensed on-device model using a consensual, representative benchmark before choosing one. Measure precision/recall, false positives/negatives, calibration, subgroup performance, latency, memory and battery use. Video needs a measured sampling/aggregation strategy. Use explicitly shared media or a guardian-approved local source; avoid uploading private media. Keep inference local, avoid retaining source images, communicate uncertainty and provide correction/appeal controls. Review SDK telemetry separately. No model or new media collection was enabled during this task.

## Website and payments

The website/checkout source is absent from this workspace. Backend compatibility endpoints are present and tested: role-specific login, protected child lookup, and service-token premium synchronization with consistent child identity. The lookup contract now requires a trusted website server proxy; never embed the service token in browser code.

Premium synchronization is not verified payment activation. Real activation needs merchant approval and credentials, server verification of signed transactions/webhooks, order/child binding, amount/currency validation, replay protection, idempotency, refund/reversal handling and a staging-to-live acceptance test. Do not trust a client-reported checkout success. Keep real payments disabled until these gates pass.
