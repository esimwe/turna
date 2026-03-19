const storageKey = "turna_web_session_v1";
const activeChatStorageKey = "turna_web_active_chat_v1";
const qrPollIntervalMs = 2000;

const state = {
  session: null,
  user: null,
  chats: [],
  activeChatId: null,
  activeChatDetail: null,
  messagesByChatId: new Map(),
  qrRequest: null,
  qrPollTimer: null,
  qrPollBusy: false,
  socket: null,
  socketConnected: false,
  joinedChatIds: new Set(),
  chatRefreshTimer: null
};

const $ = (selector) => document.querySelector(selector);

const refs = {
  loginView: $("#login-view"),
  appView: $("#app-view"),
  qrCanvas: $("#qr-canvas"),
  qrStatusTitle: $("#qr-status-title"),
  qrStatusText: $("#qr-status-text"),
  refreshQrButton: $("#refresh-qr-button"),
  downloadQrLink: $("#download-qr-link"),
  connectionChip: $("#connection-chip"),
  logoutButton: $("#logout-button"),
  currentUserName: $("#current-user-name"),
  sidebarStatus: $("#sidebar-status"),
  chatList: $("#chat-list"),
  activeChatName: $("#active-chat-name"),
  activeChatMeta: $("#active-chat-meta"),
  messageList: $("#message-list"),
  composerForm: $("#composer-form"),
  composerInput: $("#composer-input"),
  composerSend: $("#composer-send"),
  refreshChatsButton: $("#refresh-chats-button")
};

refs.refreshQrButton.addEventListener("click", () => {
  void startQrLogin({ force: true });
});

refs.logoutButton.addEventListener("click", () => {
  void logout();
});

refs.refreshChatsButton.addEventListener("click", () => {
  void refreshChats({ silentLabel: false });
});

refs.composerForm.addEventListener("submit", (event) => {
  event.preventDefault();
  void sendComposerMessage();
});

refs.composerInput.addEventListener("input", () => {
  refs.composerInput.style.height = "auto";
  refs.composerInput.style.height = `${Math.min(refs.composerInput.scrollHeight, 160)}px`;
});

function loadStoredSession() {
  const raw = localStorage.getItem(storageKey);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (
      !parsed ||
      typeof parsed !== "object" ||
      typeof parsed.accessToken !== "string" ||
      parsed.accessToken.trim().length === 0
    ) {
      return null;
    }
    return {
      accessToken: parsed.accessToken.trim(),
      user: parsed.user && typeof parsed.user === "object" ? parsed.user : null
    };
  } catch {
    return null;
  }
}

function storeSession(session) {
  state.session = session;
  localStorage.setItem(storageKey, JSON.stringify(session));
}

function clearStoredSession() {
  localStorage.removeItem(storageKey);
  state.session = null;
  state.user = null;
  state.chats = [];
  state.activeChatId = null;
  state.activeChatDetail = null;
  state.messagesByChatId = new Map();
  state.joinedChatIds = new Set();
  localStorage.removeItem(activeChatStorageKey);
}

function readActiveChatId() {
  const raw = localStorage.getItem(activeChatStorageKey) || "";
  return raw.trim() || null;
}

function storeActiveChatId(chatId) {
  if (!chatId) {
    localStorage.removeItem(activeChatStorageKey);
    return;
  }
  localStorage.setItem(activeChatStorageKey, chatId);
}

function setConnectionLabel(text) {
  refs.connectionChip.textContent = text;
}

function setQrStatus(title, text) {
  refs.qrStatusTitle.textContent = title;
  refs.qrStatusText.textContent = text;
}

function setSidebarStatus(text) {
  refs.sidebarStatus.textContent = text;
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function formatClock(iso) {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("tr-TR", {
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function formatChatListTime(iso) {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  const now = new Date();
  const sameDay =
    now.getFullYear() === date.getFullYear() &&
    now.getMonth() === date.getMonth() &&
    now.getDate() === date.getDate();
  if (sameDay) {
    return formatClock(iso);
  }
  return new Intl.DateTimeFormat("tr-TR", {
    day: "2-digit",
    month: "2-digit"
  }).format(date);
}

function sortByCreatedAtAsc(left, right) {
  return new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime();
}

function buildInitials(label) {
  const parts = (label || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2);
  if (parts.length === 0) return "T";
  return parts.map((item) => item[0].toUpperCase()).join("");
}

function describeMessage(message) {
  const text = (message?.text || "").trim();
  if (text) return text;
  if (!Array.isArray(message?.attachments) || message.attachments.length === 0) {
    return "Mesaj";
  }
  const first = message.attachments[0];
  if (first.kind === "image") return "Fotoğraf";
  if (first.kind === "video") return "Video";
  return first.fileName?.trim() || "Dosya";
}

function describeAttachment(attachment) {
  if (!attachment) return "Ek";
  if (attachment.kind === "image") return "Fotoğraf";
  if (attachment.kind === "video") return "Video";
  return attachment.fileName?.trim() || "Dosya";
}

function buildBrowserLabel() {
  const ua = navigator.userAgent || "";
  if (/Safari/i.test(ua) && !/Chrome|CriOS|Edg/i.test(ua)) {
    return "Turna Web • Safari";
  }
  if (/Edg/i.test(ua)) {
    return "Turna Web • Edge";
  }
  if (/Firefox/i.test(ua)) {
    return "Turna Web • Firefox";
  }
  if (/Chrome|CriOS/i.test(ua)) {
    return "Turna Web • Chrome";
  }
  return "Turna Web";
}

async function requestJson(path, options = {}, auth = true) {
  const headers = new Headers(options.headers || {});
  if (options.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (auth && state.session?.accessToken) {
    headers.set("Authorization", `Bearer ${state.session.accessToken}`);
  }

  const response = await fetch(path, {
    ...options,
    headers
  });
  const text = await response.text();
  let payload = {};
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = { raw: text };
    }
  }
  return { ok: response.ok, status: response.status, payload };
}

async function api(path, options = {}, auth = true) {
  const result = await requestJson(path, options, auth);
  if (!result.ok) {
    const error = new Error(result.payload?.error || `request_failed_${result.status}`);
    error.status = result.status;
    error.payload = result.payload;
    if (auth && result.status === 401) {
      await forceLogout("Oturum kapandı. QR ile tekrar bağlan.");
    }
    throw error;
  }
  return result.payload;
}

function disconnectSocket() {
  if (!state.socket) return;
  state.socket.removeAllListeners();
  state.socket.disconnect();
  state.socket = null;
  state.socketConnected = false;
}

function stopQrPolling() {
  if (state.qrPollTimer != null) {
    window.clearInterval(state.qrPollTimer);
    state.qrPollTimer = null;
  }
  state.qrPollBusy = false;
}

async function forceLogout(reason) {
  stopQrPolling();
  disconnectSocket();
  clearStoredSession();
  setConnectionLabel("Bağlı değil");
  if (reason) {
    setQrStatus("Oturum kapandı", reason);
  }
  renderShell();
  await startQrLogin({ force: true, preserveStatus: Boolean(reason) });
}

async function logout() {
  try {
    await api("/api/auth/logout", { method: "POST" });
  } catch (_) {}
  await forceLogout("Çıkış yapıldı. Yeni QR hazırlandı.");
}

function renderShell() {
  const authenticated = Boolean(state.session?.accessToken);
  refs.loginView.classList.toggle("hidden", authenticated);
  refs.appView.classList.toggle("hidden", !authenticated);
  refs.composerInput.disabled = !authenticated || !state.activeChatId;
  refs.composerSend.disabled = !authenticated || !state.activeChatId;
}

function renderChatList() {
  if (state.chats.length === 0) {
    refs.chatList.innerHTML = `
      <div class="empty-state">
        <h3>Sohbet yok</h3>
        <p>Mobilde bir sohbet açtığında burada belirecek.</p>
      </div>
    `;
    return;
  }

  refs.chatList.innerHTML = state.chats
    .map((chat) => {
      const preview = escapeHtml((chat.lastMessage || "").trim() || "Henüz mesaj yok");
      const activeClass = chat.chatId === state.activeChatId ? " active" : "";
      const unread = chat.unreadCount > 0 ? `<span class="unread-badge">${chat.unreadCount}</span>` : "";
      return `
        <button class="chat-item${activeClass}" type="button" data-chat-id="${chat.chatId}">
          <div class="avatar-pill">${escapeHtml(buildInitials(chat.title || chat.name || "Turna"))}</div>
          <div class="chat-item-main">
            <div class="chat-item-top">
              <div class="chat-item-name">${escapeHtml(chat.title || chat.name || "Sohbet")}</div>
            </div>
            <div class="chat-item-preview">${preview}</div>
          </div>
          <div class="chat-item-side">
            <div class="chat-time">${escapeHtml(formatChatListTime(chat.lastMessageAt))}</div>
            ${unread}
          </div>
        </button>
      `;
    })
    .join("");

  refs.chatList.querySelectorAll("[data-chat-id]").forEach((button) => {
    button.addEventListener("click", () => {
      const chatId = button.getAttribute("data-chat-id");
      if (!chatId) return;
      void selectChat(chatId);
    });
  });
}

function renderMessages() {
  const chatId = state.activeChatId;
  if (!chatId) {
    refs.messageList.classList.add("empty");
    refs.messageList.innerHTML = `
      <div class="empty-state">
        <h3>Sohbet seç</h3>
        <p>Mesajlar burada görünecek.</p>
      </div>
    `;
    return;
  }

  const messages = state.messagesByChatId.get(chatId) || [];
  if (messages.length === 0) {
    refs.messageList.classList.add("empty");
    refs.messageList.innerHTML = `
      <div class="empty-state">
        <h3>Henüz mesaj yok</h3>
        <p>Mesajlar arka planda yenileniyor.</p>
      </div>
    `;
    return;
  }

  refs.messageList.classList.remove("empty");
  refs.messageList.innerHTML = `
    <div class="message-stack">
      ${messages
        .map((message) => {
          const mine = message.senderId === state.user?.id;
          const senderLabel = mine
            ? "Siz"
            : (message.senderDisplayName || state.activeChatDetail?.title || "Turna").trim();
          const attachmentMarkup = Array.isArray(message.attachments)
            ? message.attachments
                .map(
                  (attachment) =>
                    `<div class="attachment-chip">${escapeHtml(describeAttachment(attachment))}</div>`
                )
                .join("")
            : "";
          return `
            <div class="message-row${mine ? " mine" : ""}">
              <article class="message-bubble">
                ${mine ? "" : `<div class="message-sender">${escapeHtml(senderLabel)}</div>`}
                <div class="message-text">${escapeHtml(describeMessage(message))}</div>
                ${attachmentMarkup}
                <div class="message-meta">${escapeHtml(formatClock(message.createdAt))}</div>
              </article>
            </div>
          `;
        })
        .join("")}
    </div>
  `;
}

function scrollMessagesToBottom() {
  refs.messageList.scrollTop = refs.messageList.scrollHeight;
}

function renderActiveChatHeader() {
  const activeChat = state.chats.find((item) => item.chatId === state.activeChatId) || null;
  if (!activeChat) {
    refs.activeChatName.textContent = "Sohbet seç";
    refs.activeChatMeta.textContent = "Sol listeden bir sohbet aç.";
    return;
  }
  refs.activeChatName.textContent = activeChat.title || activeChat.name || "Sohbet";
  refs.activeChatMeta.textContent =
    state.activeChatDetail?.chatType === "group"
      ? `${state.activeChatDetail.memberCount || 0} katılımcı`
      : "Mesajlar arka planda yenileniyor.";
}

function setChats(nextChats) {
  state.chats = nextChats
    .map((chat) => ({
      ...chat,
      name: chat.title || chat.name || "Sohbet"
    }))
    .sort((left, right) => new Date(right.lastMessageAt || 0).getTime() - new Date(left.lastMessageAt || 0).getTime());
  if (!state.activeChatId || !state.chats.some((chat) => chat.chatId === state.activeChatId)) {
    state.activeChatId = state.chats[0]?.chatId || null;
  }
  if (state.activeChatId) {
    storeActiveChatId(state.activeChatId);
  }
}

function upsertMessages(chatId, incoming) {
  const current = state.messagesByChatId.get(chatId) || [];
  const byId = new Map(current.map((message) => [message.id, message]));
  for (const message of incoming) {
    byId.set(message.id, { ...(byId.get(message.id) || {}), ...message });
  }
  const next = Array.from(byId.values()).sort(sortByCreatedAtAsc);
  state.messagesByChatId.set(chatId, next);
}

async function refreshChats({ silentLabel = true } = {}) {
  if (!silentLabel) {
    setSidebarStatus("Sohbetler arka planda yenileniyor.");
  }
  const payload = await api("/api/chats");
  setChats(payload.data || []);
  renderChatList();
  renderActiveChatHeader();
  if (state.activeChatId) {
    await selectChat(state.activeChatId, { preserveScroll: true, silent: true });
  }
  setSidebarStatus(state.chats.length > 0 ? "Güncel." : "Henüz sohbet yok.");
}

async function refreshChatMessages(chatId) {
  const payload = await api(`/api/chats/${encodeURIComponent(chatId)}/messages?limit=50`);
  upsertMessages(chatId, payload.data || []);
  renderMessages();
}

async function refreshChatDetail(chatId) {
  const payload = await api(`/api/chats/${encodeURIComponent(chatId)}`);
  state.activeChatDetail = payload.data || null;
  renderActiveChatHeader();
}

async function markActiveChatRead(chatId) {
  try {
    await api(`/api/chats/${encodeURIComponent(chatId)}/read`, { method: "POST" });
  } catch (_) {}
}

async function selectChat(chatId, options = {}) {
  if (!chatId) return;
  const changed = state.activeChatId !== chatId;
  state.activeChatId = chatId;
  storeActiveChatId(chatId);
  renderChatList();
  renderActiveChatHeader();
  renderMessages();

  if (!state.joinedChatIds.has(chatId) && state.socketConnected) {
    state.socket.emit("chat:join", { chatId });
    state.joinedChatIds.add(chatId);
  }

  await Promise.allSettled([refreshChatDetail(chatId), refreshChatMessages(chatId)]);
  await markActiveChatRead(chatId);
  if (changed || !options.preserveScroll) {
    scrollMessagesToBottom();
  }
}

async function sendComposerMessage() {
  const chatId = state.activeChatId;
  if (!chatId) return;
  const text = refs.composerInput.value.trim();
  if (!text) return;

  refs.composerSend.disabled = true;
  try {
    const payload = await api("/api/chats/messages", {
      method: "POST",
      body: JSON.stringify({
        chatId,
        text,
        attachments: []
      })
    });
    refs.composerInput.value = "";
    refs.composerInput.style.height = "auto";
    if (payload.data) {
      upsertMessages(chatId, [payload.data]);
      renderMessages();
      scrollMessagesToBottom();
    }
    await refreshChats();
  } finally {
    refs.composerSend.disabled = false;
  }
}

function schedulePassiveChatRefresh() {
  if (state.chatRefreshTimer != null) {
    window.clearTimeout(state.chatRefreshTimer);
  }
  state.chatRefreshTimer = window.setTimeout(() => {
    void refreshChats({ silentLabel: true });
  }, 250);
}

function attachSocket() {
  if (!window.io || !state.session?.accessToken) return;
  disconnectSocket();
  state.socket = window.io({
    auth: {
      token: state.session.accessToken
    }
  });

  state.socket.on("connect", () => {
    state.socketConnected = true;
    setConnectionLabel("Canlı");
    if (state.activeChatId && !state.joinedChatIds.has(state.activeChatId)) {
      state.socket.emit("chat:join", { chatId: state.activeChatId });
      state.joinedChatIds.add(state.activeChatId);
    }
  });

  state.socket.on("disconnect", () => {
    state.socketConnected = false;
    setConnectionLabel("Bağlantı yeniden kuruluyor");
  });

  state.socket.on("chat:inbox:update", () => {
    schedulePassiveChatRefresh();
  });

  state.socket.on("chat:message", (message) => {
    if (!message?.chatId) return;
    upsertMessages(message.chatId, [message]);
    if (message.chatId === state.activeChatId) {
      renderMessages();
      scrollMessagesToBottom();
      void markActiveChatRead(message.chatId);
    }
    schedulePassiveChatRefresh();
  });

  state.socket.on("chat:status", (payload) => {
    if (!payload?.chatId || !Array.isArray(payload.messageIds)) return;
    const current = state.messagesByChatId.get(payload.chatId) || [];
    const messageIds = new Set(payload.messageIds);
    const next = current.map((message) =>
      messageIds.has(message.id) ? { ...message, status: payload.status } : message
    );
    state.messagesByChatId.set(payload.chatId, next);
    if (payload.chatId === state.activeChatId) {
      renderMessages();
    }
  });

  state.socket.on("auth:session_revoked", () => {
    void forceLogout("Bu web oturumu kaldırıldı. Yeni QR hazırlandı.");
  });
}

let qrLogoPromise = null;

function loadQrLogo() {
  if (qrLogoPromise) return qrLogoPromise;
  qrLogoPromise = new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = "/web/assets/turna-icon.png";
  });
  return qrLogoPromise;
}

async function renderQrCode(text) {
  const qrFactory = window.qrcode;
  if (typeof qrFactory !== "function") {
    throw new Error("qr_generator_missing");
  }

  const qr = qrFactory(0, "H");
  qr.addData(text);
  qr.make();

  const canvas = refs.qrCanvas;
  const context = canvas.getContext("2d");
  const size = 320;
  const margin = 20;
  const moduleCount = qr.getModuleCount();
  const cellSize = Math.floor((size - margin * 2) / moduleCount);
  const qrSize = cellSize * moduleCount;
  const offset = Math.floor((size - qrSize) / 2);

  canvas.width = size;
  canvas.height = size;
  context.clearRect(0, 0, size, size);
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, size, size);

  context.fillStyle = "#183633";
  for (let y = 0; y < moduleCount; y += 1) {
    for (let x = 0; x < moduleCount; x += 1) {
      if (!qr.isDark(x, y)) continue;
      context.fillRect(offset + x * cellSize, offset + y * cellSize, cellSize, cellSize);
    }
  }

  const logoBoxSize = Math.round(qrSize * 0.22);
  const logoBoxX = Math.round((size - logoBoxSize) / 2);
  const logoBoxY = Math.round((size - logoBoxSize) / 2);
  const logoPadding = Math.round(logoBoxSize * 0.18);
  const logoImage = await loadQrLogo();

  context.fillStyle = "#ffffff";
  context.strokeStyle = "#183633";
  context.lineWidth = 4;
  drawRoundedRect(context, logoBoxX, logoBoxY, logoBoxSize, logoBoxSize, 26);
  context.fill();
  context.stroke();
  context.drawImage(
    logoImage,
    logoBoxX + logoPadding,
    logoBoxY + logoPadding,
    logoBoxSize - logoPadding * 2,
    logoBoxSize - logoPadding * 2
  );

  refs.downloadQrLink.href = canvas.toDataURL("image/png");
}

function drawRoundedRect(context, x, y, width, height, radius) {
  context.beginPath();
  context.moveTo(x + radius, y);
  context.arcTo(x + width, y, x + width, y + height, radius);
  context.arcTo(x + width, y + height, x, y + height, radius);
  context.arcTo(x, y + height, x, y, radius);
  context.arcTo(x, y, x + width, y, radius);
  context.closePath();
}

async function pollQrStatus() {
  if (!state.qrRequest || state.qrPollBusy) return;
  state.qrPollBusy = true;
  try {
    const result = await requestJson(
      `/api/auth/web-login/request/${encodeURIComponent(state.qrRequest.requestId)}?secret=${encodeURIComponent(state.qrRequest.secret)}`,
      {},
      false
    );

    if (!result.ok) {
      if (result.status === 410 || result.payload?.error === "web_login_expired") {
        setQrStatus("QR süresi doldu", "Kod otomatik yenileniyor.");
        await startQrLogin({ force: true, preserveStatus: true });
      }
      return;
    }

    const status = result.payload?.data;
    if (status?.status === "approved" && typeof status.accessToken === "string") {
      storeSession({
        accessToken: status.accessToken,
        user: status.user || null
      });
      stopQrPolling();
      await enterApp();
    }
  } catch (_) {
    setQrStatus("Bağlantı bekleniyor", "Ağ kesildi. QR arka planda yeniden denenecek.");
  } finally {
    state.qrPollBusy = false;
  }
}

async function startQrLogin({ force = false, preserveStatus = false } = {}) {
  if (state.qrRequest && !force) return;
  stopQrPolling();
  state.qrRequest = null;
  renderShell();
  setConnectionLabel("Bağlı değil");
  if (!preserveStatus) {
    setQrStatus("QR hazırlanıyor", "Yeni bağlantı isteği oluşturuluyor.");
  }

  try {
    const payload = await api(
      "/api/auth/web-login/request",
      {
        method: "POST",
        body: JSON.stringify({
          deviceLabel: buildBrowserLabel()
        })
      },
      false
    );
    state.qrRequest = payload.data;
    await renderQrCode(payload.data.qrText);
    setQrStatus("Telefonundan okut", "Turna uygulamasında Bağlı cihazlar ekranını açıp QR'ı tara.");
    state.qrPollTimer = window.setInterval(() => {
      void pollQrStatus();
    }, qrPollIntervalMs);
    void pollQrStatus();
  } catch (error) {
    setQrStatus(
      "QR oluşturulamadı",
      "Web login isteği açılamadı. QR'ı yenile ile tekrar dene."
    );
    console.error(error);
  }
}

async function enterApp() {
  renderShell();
  setConnectionLabel("Bağlanıyor");

  try {
    const mePayload = await api("/api/auth/me");
    state.user = mePayload.data || state.session?.user || null;
    refs.currentUserName.textContent = state.user?.displayName || state.user?.username || "Turna";
    setSidebarStatus("Sohbetler arka planda yenileniyor.");
    state.activeChatId = readActiveChatId();
    attachSocket();
    await refreshChats({ silentLabel: true });
    renderChatList();
    renderActiveChatHeader();
    renderMessages();
    setConnectionLabel(state.socketConnected ? "Canlı" : "Hazır");
  } catch (error) {
    console.error(error);
    if (!state.session?.accessToken) {
      return;
    }
    await forceLogout("Web oturumu doğrulanamadı. Yeni QR hazırlandı.");
  }
}

async function bootstrap() {
  renderShell();
  refs.downloadQrLink.removeAttribute("href");
  state.session = loadStoredSession();
  if (state.session?.accessToken) {
    await enterApp();
    return;
  }
  await startQrLogin();
}

void bootstrap();
