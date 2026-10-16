# Message Up — Native Flutter App (App Edition)

**Eita website na, TWA na — pure native Flutter app.** Play Store-e jabe AAB hishebe, phone-e real app-er moto cholbe: fast, smooth, offline-friendly.

> ⚠️ Honest kotha: web version-er 40+ feature shob ekbare ei prothom native cut-e ana hoy nai. Core jinish — auth, chats, messages, ticks, status, feed, profile, settings, admin — shotti + Firestore-e wired. Calls screen ekhon UI + wiring TODO (niche dekho). Baki web feature gula porer cut-e ashbe, ekta ekta kore, test kore.

---

## Ki ki real + wired (ei build-e)

- **Google Sign-In** — kono password nai, kothao nai.
- **Chats** — Firestore `chats` stream, search, unread badge, archive / mute / block.
- **Messages** — send, reply, forward (target picker next cut), star, delete, ticks (sent / delivered / read), disappearing messages (1 min / 1h / 24h / 7d).
- **Status** — 24h status post + list, expiry filter.
- **Feed** — post create, like/unlike, comment — shob Firestore `posts`-e.
- **Profile** — name / about edit, online dot.
- **Settings** — dark theme, speed mode, ghost mode, Vault PIN (SHA-256 hash hishebe save, PIN kokhono save hoy na), app lock.
- **Admin Panel** — Dashboard (counts) / Users / Reports. **Sudhu admin account-er jonno** — admin email allowlist `lib/utils/constants.dart`-e **ek jaygay** ache; onno keu panel dekhte parbe na, "Not admin" dekhbe. Admin check synchronous, kono Firestore dependency nai, kono password nai.

## Ki TODO (build bhangbe na)

- **Calls (WebRTC):** `lib/screens/calls_screen.dart`-er header-e full wiring steps lekha ache — `flutter_webrtc` add kora, Firestore signalling (`calls/{callId}`), permission handling. Ekhn UI preview matro.
- **Forward target picker:** chat list theke target choose kora — next cut.
- **Photo status / image messages:** `image_picker` + Firebase Storage already pubspec-e ache, wiring next cut.

---

## Build steps (PC thakle)

```bash
# 1. Flutter SDK install koro: https://docs.flutter.dev/get-started/install
flutter --version

# 2. Project folder-e jao
cd message-up-flutter

# 3. Dependencies
flutter pub get

# 4. Firebase connect (REAL keys ekhane generate hobe — chat-e / file-e kokhono haate likhba na)
dart pub global activate flutterfire_cli
flutterfire configure

# 5. Run (emulator / USB phone)
flutter run

# 6. Release AAB (Play Store-er jonno)
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

> `lib/firebase_options.dart` ekhon **TEMPLATE** — `{{...}}` placeholder matro, kono real key nai. `flutterfire configure` chalalei real value auto-generate hobe. Kokhono real key copy-paste kore commit korba na.

---

## Phone-friendly build (PC CHARA — Codemagic cloud build)

PC na thakle phone thekei AAB + APK banano jay. `codemagic.yaml` ALREADY repo-te ache — Codemagic eta auto-detect korbe. Pura flow-ta straight success path — ektar por ekta step koro:

**Step 1 — GitHub-e push koro:** ei `message-up-flutter/` folder-er **CONTENTS** repo ROOT-e upload koro — `pubspec.yaml`, `lib/`, `codemagic.yaml` shob top level-e, `message-up-flutter/` subfolder-er bhitore na.

**Step 2 — Firebase setup (ekbar-er kaj):**
- Firebase Console → Project settings → **Android app** (`com.murad.message_up`) → **google-services.json download** kore repo ROOT-e rakho (pubspec.yaml-er pashe). Workflow eta nije `android/app/`-e copy kore nibe.
- Firebase Console → Project settings → **Your apps → Web app** theke asol value niye `lib/firebase_options.dart`-er `{{...}}` jaygagulo voro. Na vorle app setup screen dekhabe (crash korbe na).

**Step 3 — Codemagic:** **codemagic.io**-te free account khulo → GitHub diye login → **Add application** → tomar repo select koro → `codemagic.yaml` peye workflow auto-load hobe → **Start build**.

**Step 4 — SHA-1 (ekbar-er kaj, sign-in-er jonno):** Prothom build-er log-e **"Print debug keystore SHA-1"** step-e SHA-1 lekha thakbe. Oita copy kore Firebase Console → Project settings → Android app → **SHA certificate fingerprints → Add fingerprint** → Save koro. Tarpor **arekbar build** dao. Ekhon theke Google Sign-In cholbe.

**Step 5 — Install + test:** Build shesh hole **app-release.apk** download kore phone-e install koro → Google diye login → chat test. **app-release.aab** ta Play Store-er jonno rekhe dao (phone-e install hoy na).

> `codemagic.yaml` prothom step-e `flutter create --platforms=android .` chalabe, karon project-e ekhono `android/` folder nai. Eta `--overwrite` chara chole, tai `lib/` + `pubspec.yaml` kichui bodlabe na — shudhu missing Android scaffold banabe, applicationId `com.murad.message_up` diye. Ei ID pore bodlano jay na.

> Codemagic free tier-e mashe kichu build minutes free thake — Message Up-er size-er app-er jonno jothesto.

---

## Play Store recap

- **Play Console** account + **$25** one-time fee.
- **Play App Signing:** Console-e AAB upload korlei Google signing handle kore.
- **Privacy policy URL:** V5 web app-er `privacy.html` reuse koro — same URL, notun kore likhte hobe na.
- **Listing:** icon, screenshots, short/long description, content rating, data safety form.
- **Test:** age **closed testing** (nije + koyekjon) → tarpor **production**.

---

## Firestore rules (mone rakhba)

Rules-e ei niyom gula rakho: user sudhu nijer member-hoya chat porte/likhte parbe; admin panel-er data (reports) sudhu admin email-er account porte parbe. Rules na dile app crash korbe na, kintu Firestore permission error toast/log-e dekhabe.

## Security notes

- Kono password, API key, Firebase key ei repo-te nai — shob placeholder.
- Admin allowlist ek jaygay matro (`lib/utils/constants.dart`).
- Vault PIN sudhu SHA-256 hash hishebe thake.
- Photo / doc / voice — kokhono upload hoy na jotokkhon tumi pathao na.
