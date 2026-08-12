# Store release gate

This file is the short go/no-go gate. The detailed Arabic procedure is in `FINAL_RELEASE_STEPS_AR.md`.

Release only when every item is true:

- All four Supabase migrations have been applied in filename order and backed up.
- RLS and RPC grants were verified in production; no mobile role can read activation tables directly.
- The HTTPS backend is deployed, healthy, authenticated, rate-limited, and all provider secrets remain server-side.
- Privacy and account-deletion pages are publicly reachable over HTTPS.
- `flutter pub get`, `flutter analyze`, `flutter test`, Android AAB build, and iOS IPA/archive build all pass in the signing environment.
- Release builds were tested on physical Android and iOS devices, including camera, gallery, PDF, microphone, speech recognition, TTS, recording, poor network, background/resume, activation and deletion.
- Google Play Data Safety, Health Apps, generative-AI reporting, and account-deletion declarations match production behavior.
- Apple App Privacy, age rating, account deletion, export compliance, and medical/educational positioning match production behavior.
- Store review notes include tested reviewer-only activation codes and exact access steps, never an admin credential.
- Store text never markets AI output as a diagnosis, approved radiology report, or substitute for a clinician.
- No API secret, service-role key, signing file, certificate, password, private patient data, build cache, or debug artifact is included.

The source package alone is not a signed store artifact. Upload the generated `.aab` to Google Play and the Xcode archive/IPA through App Store Connect.
