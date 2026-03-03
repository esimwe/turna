# Turna Mobile

Flutter tabanli iOS + Android uygulamasi.

## Tamamlananlar

- WhatsApp benzeri `Chats` liste ekrani
- `Settings` -> `Profile` -> `Account` -> `Security notifications` akisi
- Socket.IO ile canli mesaj odasi (`chat:join`, `chat:send`, `chat:history`, `chat:message`)

## Calistirma

```bash
cd /Users/black/Desktop/turna/mobile_flutter
flutter pub get
flutter run
```

## Backend baglantisi

`lib/main.dart` icindeki Socket host kurali:

- Android emulator: `10.0.2.2:4000`
- iOS simulator: `localhost:4000`

Backendin ayakta olmasi gerekir:

```bash
cd /Users/black/Desktop/turna
npm --prefix backend run prisma:generate
npm --prefix backend run prisma:push
npm --prefix backend run dev
```
