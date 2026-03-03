# Turna

WhatsApp benzeri ama Turna ozellikleri olan chat uygulamasi.

## Monorepo Yapisi

- `backend`: Node.js + TypeScript + Socket.IO + Redis
- `mobile_flutter`: Flutter mobil uygulamasi (iOS + Android)
- `docs`: Tasarim ve teknik notlar

## Baslangic (Backend)

```bash
cd /Users/black/Desktop/turna
cp backend/.env.example backend/.env
npm --prefix backend install
npm --prefix backend run prisma:generate
npm --prefix backend run prisma:push
npm --prefix backend run dev
```

Saglik kontrolu:

- `GET http://localhost:4000/api/health`
- `GET http://localhost:4000/api/chats/{chatId}/messages`
- `POST http://localhost:4000/api/chats/messages`
- `POST http://localhost:4000/api/auth/request-otp`
- `POST http://localhost:4000/api/auth/verify-otp`
- `GET http://localhost:4000/api/auth/me` (Bearer token)

## Altyapi (Postgres + Redis)

```bash
docker compose up -d
```

## Railway Deploy

Repo kokunde `railway.json` ve `package.json` bulunduğu icin Railway kökten deploy edebilir.

Gerekli environment variables:

- `DATABASE_URL`
- `REDIS_URL`
- `JWT_SECRET`
- `NODE_ENV=production`
- `CORS_ORIGIN=*`

## Sonraki Adim

1. Flutter CLI kurup `mobile_flutter` icinde app scaffold olustur.
2. Chat list ve settings ekranlarini tasarimdaki gorunuce yaklastir.
3. Socket.IO ile `chat:join` / `chat:send` baglantisini ac.
4. OTP akisini Flutter login ekranina bagla.
