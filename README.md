# Budget Web

Browser-only wallet (accounts, categories, transactions) as a Flutter **web PWA**.
No diary, notes, vault, or Play/App Store — open in Chrome, Edge, Safari, or mobile browsers and optionally **Add to Home Screen**.

Sibling of Budget Pro (`new budget`). Data lives in this browser’s local storage.

## Features

- Accounts with opening balance and live balance as of selected day
- Income / Expense / Transfer
- Week/month calendar + day list
- Optional family-member tag
- Search (title, note, account, member, amount)
- Download / share JSON backup
- Import Budget Pro `.budgetpro` / `.json` (wallet tables only)
- Account statement text export

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) 3.x with web enabled  
  `flutter config --enable-web`

## Run (dev)

```bash
cd D:/projects/budget_web
flutter pub get
flutter run -d chrome
```

Other devices: `flutter devices` then `flutter run -d <id>`.

## Build (static host / PWA)

```bash
cd D:/projects/budget_web
flutter build web
```

Output: `build/web/`. Host that folder on any static HTTPS host (GitHub Pages, Netlify, nginx, etc.).

Local preview of the release build:

```bash
# Python example
cd build/web
python -m http.server 8080
# open http://localhost:8080
```

### Install as PWA

1. Open the HTTPS URL (or localhost) in Chrome / Safari / Edge  
2. **Add to Home Screen** / Install app  
3. Works offline for already-loaded assets; wallet data stays on that device/browser

## Backup & import

| Action | Where |
|--------|--------|
| Download backup | Settings → Download backup |
| Share | Settings → Share backup |
| Import Budget Pro | Settings → Import Budget Pro / JSON |

Import reads only `accounts`, `categories`, and `transactions` from Budget Pro single-profile or all-profiles backups (diary/vault ignored). Default is **replace** after confirmation.

## Project layout

```
lib/
  main.dart
  app_theme.dart
  models/models.dart
  data/local_store.dart
  data/budget_pro_import.dart
  services/backup_share.dart
  screens/wallet_screen.dart
  screens/settings_backup_screen.dart
  widgets/balance_card.dart
  widgets/tx_editor_sheet.dart
web/   # PWA manifest + icons
```

## Notes

- Clearing browser site data clears the wallet — export first.
- Each browser profile has its own storage (Chrome ≠ Safari).
- Currency symbol defaults to ₹ in the UI (amounts are plain numbers in JSON).
