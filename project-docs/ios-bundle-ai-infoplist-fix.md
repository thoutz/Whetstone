# iOS: AI_BASE_URL missing on device (Configuration alert)

## Symptom

On a physical iPhone, tapping chat showed a **Configuration** alert complaining about missing **`AI_API_KEY`** / AI setup, even though **`INFOPLIST_KEY_AI_BASE_URL`** (and related keys) were set in the Xcode target build settings.

Simulator or “Run” from Xcode could still work because the **scheme** injects **`AI_API_KEY`** into `ProcessInfo.environment`; that path never ran on a normal device launch.

## Root cause

1. **`INFOPLIST_KEY_AI_BASE_URL` did not appear in the built `Info.plist`**  
   A clean `xcodebuild` + `plutil` on `Whetstone.app/Info.plist` showed **no** `AI_BASE_URL`, `AI_MODEL`, or `AI_APP_TOKEN` entries — only generated keys like camera usage strings. So `Bundle.main` could not read a proxy URL.

2. **`makeAIClient()` logic**  
   With an empty `AI_BASE_URL`, the factory falls through to **direct Groq**, which requires **`AI_API_KEY`**. On device that env var is empty → **`AIError.missingAPIKey`** → `ConversationStore` shows **`NoopAIClient`** and surfaces the configuration alert.

The VPS / HTTPS work was unrelated to this: the app never left the device with a usable base URL.

## Fix

- Added **`Whetstone/Info.plist`** containing **`AI_BASE_URL`**, **`AI_MODEL`**, and **`AI_APP_TOKEN`** (empty unless you enable proxy auth).
- Set **`INFOPLIST_FILE = Whetstone/Info.plist`** on the target while keeping **`GENERATE_INFOPLIST_FILE = YES`** so Xcode **merges** this file with generated keys.
- Removed the non-functional **`INFOPLIST_KEY_AI_*`** entries from **`project.pbxproj`** for those three keys (camera / usage strings still use **`INFOPLIST_KEY_*`**).

After rebuilding, `Info.plist` inside the `.app` includes the `AI_*` keys.

## What you should do

1. **Clean build** and reinstall on the phone (Product → Clean Build Folder, then run/archive again).
2. Ensure the server has **`GROQ_API_KEY`** set in **`/etc/whetstone-proxy.env`** — otherwise the app will get **HTTP 500** from the proxy, not the missing-key alert.

## Optional hardening

- If you rely only on the proxy, remove **`AI_API_KEY`** from the shared scheme (or disable it) so Groq secrets are not duplicated in version control.
- If **`WHETSTONE_APP_TOKEN`** is set on the server, set matching **`AI_APP_TOKEN`** in **`Info.plist`** (or scheme for debug).
