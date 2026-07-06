# Design Document: Open Hansard Privacy Policy

## 1. Goal
Create a single, legally compliant, and clear Privacy Policy markdown document (`PRIVACY.md`) for the **Open Hansard** mobile app (developed by **Demopol Labs Ltd**). The policy must address UK/EU GDPR, California CCPA, Sentry telemetry usage, local storage mechanics, and Google Play Store linking requirements.

## 2. Key Compliance Requirements
- **UK/EU GDPR**: Disclose data controller (Demopol Labs Ltd), contact email (`hi@maybeitssoftware.co.uk`), lawful basis, data subject rights, and Sentry processor information.
- **California CCPA/CPRA**: Disclose consumer rights, state that no data is sold or shared, and provide mechanisms to exercise rights.
- **Google Play Store**: Provide a clear, accessible URL/policy document detailing what data is collected, processed, and shared.
- **Sentry Integration**: Disclose telemetry collection (device info, stack traces, IP masking) for stability monitoring.

## 3. Data Processing Matrix
- **Local Storage (SQLite, SharedPreferences)**: User bookmarks (saved speeches), theme settings, cached parliamentary debates, member lookup index. Stays on device.
- **Sentry (Error Monitoring)**: Platform, OS version, application version, crash stack traces. IP addresses masked at ingestion.
- **Third-Party APIs (In Transit)**: UK Parliament APIs, ONS Geography, OpenStreetMap (Nominatim), Democracy Club, OpenCouncilData, and parliamentlive.tv. Outbound HTTP requests transmit standard network headers (including client IP) to these servers. No data is stored by Demopol Labs Ltd.

## 4. Deliverables
- `PRIVACY.md` in the root of `/Users/adam/Projects/open-parliament`.

## 5. Review Checkpoints
- Verification of company legal name: Demopol Labs Ltd.
- Verification of contact email: `hi@maybeitssoftware.co.uk`.
- Clarity around Sentry data limits (no PII).
- Accurate description of local SQLite / SharedPreferences storage.
