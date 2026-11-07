# Installing Quiet on your iPhone with SideStore

Quiet is not in the App Store. A GitHub build machine makes the app file (`Quiet.ipa`),
and SideStore on your phone signs it with an Apple Account and installs it. Apple limits
such apps to 7 days; SideStore renews them.

**Which Apple Account:** use a spare one made for this, not your main one. SideStore and
iloader are community tools that ask you to sign in with it.

Steps follow the official guide at https://docs.sidestore.io/docs/installation/prerequisites
(read on 2026-11-07). If anything differs on your phone, the official guide wins.

## 1. One-time SideStore setup (needs the Mac once)

Requirements: iPhone on iOS 15 or later with a passcode set, Wi-Fi (not mobile data), and
this Mac for the initial install only.

1. On the Mac, download iloader (the DMG) from https://iloader.app and install it.
2. Plug the iPhone into the Mac with a cable. On the phone, tap **Trust** and enter your
   passcode if asked.
3. Open iloader, sign in with the spare Apple Account, select your iPhone, and choose
   **Install SideStore (Stable)**.
4. On the iPhone: **Settings → General → VPN & Device Management**, select the Apple
   Account under "Developer App", tap **Trust**. On iOS 18 and later choose
   **Allow & Restart** and enter your passcode. If **Settings → Privacy & Security →
   Developer Mode** is shown, turn it on (the phone restarts).
5. Install **LocalDevVPN** from the App Store, open it and tap **Connect**. It must be on
   whenever SideStore installs, updates or refreshes an app.
6. Open **SideStore**, sign in with the same Apple Account, go to **My Apps**, and tap the
   **7 DAYS** counter next to SideStore to finish setup. Agree if it asks to create or
   revoke a signing certificate.

## 2. Install Quiet

1. On the iPhone, open the latest release in Safari (sign in to GitHub if asked; the
   project is private): https://github.com/biskwida/quiet/releases/latest
2. Tap **Quiet.ipa** to download it.
3. Open SideStore → **My Apps** → **+** and pick `Quiet.ipa` from Downloads, or open
   the file in the Files app and share it to SideStore. LocalDevVPN must be connected.
4. Quiet appears on your home screen.

## 3. Keeping it running

- Each app shows a day counter in SideStore's My Apps. Tap it to renew before it reaches 0
  (LocalDevVPN on, Wi-Fi on). Community guides describe a Shortcuts automation that does
  this daily; the official guide only documents the manual tap.
- After an iOS update or a phone reset the pairing file can expire. Plug into the Mac,
  open iloader, and place the pairing file again.
- A free Apple Account can have 3 such apps at once.

## 4. Updating Quiet

Each new version is a new release at the link above. Download the new `Quiet.ipa` and
install it the same way; it replaces the old one and keeps your logins.

## First run

1. Tap **Add your Instagram account** and type your username (a label only).
2. Instagram's own login page appears inside the app. Sign in there; the app never sees
   the password.
3. You land in your inbox. Settings (gear, top right) has the Feed and Stories switches,
   accounts, and the Face ID lock.
