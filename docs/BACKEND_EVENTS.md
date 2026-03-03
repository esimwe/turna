# Backend Events (Socket.IO)

## Client -> Server

- `chat:join`
  - payload: `{ "chatId": "direct:userA:userB" }`

- `chat:send`
  - payload: `{ "chatId": "direct:userA:userB", "senderId": "userA", "text": "Merhaba" }`

## Server -> Client

- `chat:history`
  - payload: `ChatMessage[]`

- `chat:message`
  - payload: `ChatMessage`

- `error:validation`
  - payload: validation error object
