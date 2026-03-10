const storageKey = "turna_admin_access_token";

const state = {
  token: null,
  admin: null,
  users: [],
  selectedUser: null,
  selectedSessions: [],
  selectedChats: [],
  selectedMessages: [],
  selectedMedia: [],
  selectedChatId: null,
  activeTab: "overview",
};

const $ = (selector) => document.querySelector(selector);

const loginView = $("#login-view");
const appView = $("#app-view");
const loginForm = $("#login-form");
const loginError = $("#login-error");
const logoutButton = $("#logout-button");
const adminMeta = $("#admin-meta");
const usersList = $("#users-list");
const usersState = $("#users-state");
const detailEmpty = $("#detail-empty");
const detailView = $("#detail-view");
const detailName = $("#detail-name");
const detailSubtitle = $("#detail-subtitle");
const detailStatus = $("#detail-status");
const detailLastSeen = $("#detail-last-seen");
const detailAvatar = $("#detail-avatar");
const overviewTab = $("#tab-overview");
const sessionsTab = $("#tab-sessions");
const chatsTab = $("#tab-chats");
const mediaTab = $("#tab-media");
const userSearchForm = $("#user-search-form");
const userSearchInput = $("#user-search-input");

document.querySelectorAll(".tab-button").forEach((button) => {
  button.addEventListener("click", () => {
    state.activeTab = button.dataset.tab;
    renderTabs();
  });
});

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  loginError.classList.add("hidden");
  const username = $("#login-username").value.trim();
  const password = $("#login-password").value;

  try {
    const payload = await api("/api/admin/auth/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    }, false);
    state.token = payload.accessToken;
    localStorage.setItem(storageKey, state.token);
    await bootstrapAdmin();
  } catch (error) {
    loginError.textContent = error.message || "Giris yapilamadi.";
    loginError.classList.remove("hidden");
  }
});

logoutButton.addEventListener("click", () => {
  state.token = null;
  state.admin = null;
  state.users = [];
  state.selectedUser = null;
  state.selectedSessions = [];
  state.selectedChats = [];
  state.selectedMessages = [];
  state.selectedMedia = [];
  state.selectedChatId = null;
  localStorage.removeItem(storageKey);
  renderShell();
});

userSearchForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await loadUsers(userSearchInput.value.trim());
  } catch (error) {
    showInlineError(error);
  }
});

async function api(path, options = {}, auth = true) {
  const headers = new Headers(options.headers || {});
  if (!headers.has("Content-Type") && options.body) {
    headers.set("Content-Type", "application/json");
  }
  if (auth && state.token) {
    headers.set("Authorization", `Bearer ${state.token}`);
  }

  const response = await fetch(path, {
    ...options,
    headers,
  });

  if (response.status === 401) {
    state.token = null;
    localStorage.removeItem(storageKey);
    renderShell();
    throw new Error("Oturum gecerli degil.");
  }

  if (response.status === 204) return null;

  const text = await response.text();
  const payload = text ? safeJson(text) : {};
  if (!response.ok) {
    throw new Error(payload?.error || `Istek basarisiz (${response.status})`);
  }
  return payload;
}

function safeJson(raw) {
  try {
    return JSON.parse(raw);
  } catch (_) {
    return { raw };
  }
}

async function bootstrapAdmin() {
  const [mePayload, summaryPayload] = await Promise.all([
    api("/api/admin/auth/me"),
    api("/api/admin/dashboard/summary"),
  ]);

  state.admin = mePayload.data;
  renderShell();
  renderSummary(summaryPayload.data);
  await loadUsers("");
}

async function loadUsers(query) {
  usersState.textContent = "Yukleniyor...";
  usersState.classList.remove("hidden");
  usersList.innerHTML = "";

  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/users${search}`);
  state.users = payload.data || [];
  renderUsers();
}

async function loadUser(userId) {
  const [detailPayload, sessionsPayload, chatsPayload, mediaPayload] = await Promise.all([
    api(`/api/admin/users/${userId}`),
    api(`/api/admin/users/${userId}/sessions`),
    api(`/api/admin/users/${userId}/chats`),
    api(`/api/admin/users/${userId}/media`),
  ]);

  state.selectedUser = detailPayload.data;
  state.selectedSessions = sessionsPayload.data || [];
  state.selectedChats = chatsPayload.data || [];
  state.selectedMedia = mediaPayload.data || [];
  state.selectedChatId = null;
  state.selectedMessages = [];
  state.activeTab = "overview";
  renderUsers();
  renderDetail();
}

async function loadChatMessages(chatId) {
  state.selectedChatId = chatId;
  renderChatsTab();
  const payload = await api(`/api/admin/chats/${chatId}/messages`);
  state.selectedMessages = payload.data || [];
  renderChatsTab();
}

function renderShell() {
  const loggedIn = Boolean(state.token && state.admin);
  loginView.classList.toggle("hidden", loggedIn);
  appView.classList.toggle("hidden", !loggedIn);
  logoutButton.classList.toggle("hidden", !loggedIn);
  adminMeta.classList.toggle("hidden", !loggedIn);

  if (loggedIn) {
    adminMeta.innerHTML = `
      <strong>${escapeHtml(state.admin.displayName || "Admin")}</strong>
      <span>${escapeHtml(state.admin.username || "")}</span>
      <span>${escapeHtml(state.admin.role || "")}</span>
    `;
  } else {
    adminMeta.innerHTML = "";
    usersList.innerHTML = "";
    usersState.textContent = "Yukleniyor...";
    detailEmpty.classList.remove("hidden");
    detailView.classList.add("hidden");
  }
}

function renderSummary(summary) {
  $("#metric-total-users").textContent = formatNumber(summary.totalUsers);
  $("#metric-active-sessions").textContent = formatNumber(summary.activeSessions);
  $("#metric-messages").textContent = formatNumber(summary.messagesLast24h);
  $("#metric-open-reports").textContent = formatNumber(summary.openReports);
}

function renderUsers() {
  if (!state.users.length) {
    usersState.textContent = "Kullanici bulunamadi.";
    usersState.classList.remove("hidden");
    usersList.innerHTML = "";
    return;
  }

  usersState.classList.add("hidden");
  usersList.innerHTML = state.users
    .map((user) => {
      const active = state.selectedUser?.id === user.id ? "active" : "";
      const phone = user.phone ? formatPhone(user.phone) : "Telefon yok";
      return `
        <article class="user-card ${active}" data-user-id="${escapeHtml(user.id)}">
          <div class="user-card-head">
            ${renderAvatar(user.avatarUrl, user.displayName, "avatar")}
            <div>
              <div class="user-title">${escapeHtml(user.displayName || "-")}</div>
              <div class="user-subtitle">
                ${escapeHtml(user.username ? `@${user.username}` : phone)}
              </div>
            </div>
          </div>
          <div class="badge-row">
            <span class="status-badge ${statusClass(user.accountStatus)}">${escapeHtml(user.accountStatus || "-")}</span>
            ${user.otpBlocked ? '<span class="pill">OTP blok</span>' : ""}
            ${user.sendRestricted ? '<span class="pill">Mesaj kisit</span>' : ""}
            ${user.callRestricted ? '<span class="pill">Arama kisit</span>' : ""}
          </div>
        </article>
      `;
    })
    .join("");

  usersList.querySelectorAll("[data-user-id]").forEach((node) => {
    node.addEventListener("click", () => {
      loadUser(node.dataset.userId).catch(showInlineError);
    });
  });
}

function renderDetail() {
  if (!state.selectedUser) {
    detailEmpty.classList.remove("hidden");
    detailView.classList.add("hidden");
    return;
  }

  detailEmpty.classList.add("hidden");
  detailView.classList.remove("hidden");

  const user = state.selectedUser;
  detailName.textContent = user.displayName || "-";
  detailSubtitle.textContent = [
    user.username ? `@${user.username}` : null,
    user.phone ? formatPhone(user.phone) : null,
    user.email || null,
  ]
    .filter(Boolean)
    .join(" • ");
  detailStatus.textContent = user.accountStatus || "-";
  detailStatus.className = `status-badge ${statusClass(user.accountStatus)}`;
  detailLastSeen.textContent = user.lastSeenAt
    ? `Son gorulme ${formatDateTime(user.lastSeenAt)}`
    : "Son gorulme yok";
  detailAvatar.innerHTML = renderAvatarInner(user.avatarUrl, user.displayName);

  renderTabs();
}

function renderTabs() {
  document.querySelectorAll(".tab-button").forEach((button) => {
    button.classList.toggle("active", button.dataset.tab === state.activeTab);
  });
  overviewTab.classList.toggle("hidden", state.activeTab !== "overview");
  sessionsTab.classList.toggle("hidden", state.activeTab !== "sessions");
  chatsTab.classList.toggle("hidden", state.activeTab !== "chats");
  mediaTab.classList.toggle("hidden", state.activeTab !== "media");

  if (state.activeTab === "overview") renderOverviewTab();
  if (state.activeTab === "sessions") renderSessionsTab();
  if (state.activeTab === "chats") renderChatsTab();
  if (state.activeTab === "media") renderMediaTab();
}

function renderOverviewTab() {
  const user = state.selectedUser;
  if (!user) return;

  const latest = user.latestSession || state.selectedSessions[0] || null;
  overviewTab.innerHTML = `
    <div class="overview-grid">
      <article class="info-card">
        <h3>Profil</h3>
        <div class="kv-list">
          ${kv("Kullanici ID", user.id)}
          ${kv("Telefon", user.phone ? formatPhone(user.phone) : "-")}
          ${kv("Email", user.email || "-")}
          ${kv("Bio", user.about || "-")}
          ${kv("Olusturulma", formatDateTime(user.createdAt))}
          ${kv("Onboarding", user.onboardingCompletedAt ? "Tamamlandi" : "Bekliyor")}
        </div>
      </article>

      <article class="info-card">
        <h3>Sayilar</h3>
        <div class="kv-list">
          ${kv("Sohbet", formatNumber(user._count?.memberships || 0))}
          ${kv("Mesaj", formatNumber(user._count?.messages || 0))}
          ${kv("Cihaz token", formatNumber(user._count?.devices || 0))}
          ${kv("Tum session", formatNumber(user._count?.authSessions || 0))}
          ${kv("Aktif session", formatNumber(user.activeSessionCount || 0))}
          ${kv("Sikayet", formatNumber(user._count?.reportsAgainst || 0))}
        </div>
      </article>

      <article class="info-card">
        <h3>Son cihaz</h3>
        <div class="kv-list">
          ${kv("Model", latest?.deviceModel || "-")}
          ${kv("Platform", latest?.platform || "-")}
          ${kv("OS", latest?.osVersion || "-")}
          ${kv("Uygulama", latest?.appVersion || "-")}
          ${kv("Dil", latest?.localeTag || "-")}
          ${kv("Bolge", latest?.regionCode || "-")}
          ${kv("Baglanti", latest?.connectionType || "-")}
          ${kv("Cihaz ulkesi", latest?.countryIso || "-")}
          ${kv("IP ulkesi", latest?.ipCountryIso || "-")}
        </div>
      </article>

      <article class="info-card">
        <h3>Erisim durumu</h3>
        <div class="kv-list">
          ${kv("Hesap", user.accountStatus || "-")}
          ${kv("Durum nedeni", user.accountStatusReason || "-")}
          ${kv("OTP", user.otpBlocked ? "Bloklu" : "Acik")}
          ${kv("Mesaj", user.sendRestricted ? "Kisitli" : "Serbest")}
          ${kv("Arama", user.callRestricted ? "Kisitli" : "Serbest")}
        </div>
      </article>
    </div>
  `;
}

function renderSessionsTab() {
  if (!state.selectedSessions.length) {
    sessionsTab.innerHTML = '<div class="empty-note">Oturum kaydi bulunmuyor.</div>';
    return;
  }

  sessionsTab.innerHTML = `
    <div class="sessions-table">
      ${state.selectedSessions
        .map((session) => {
          const active = !session.revokedAt;
          return `
            <article class="session-card ${active ? "active" : ""}">
              <div class="badge-row">
                <span class="status-badge ${active ? "" : "status-suspended"}">
                  ${active ? "Aktif" : "Revoked"}
                </span>
                <span class="pill">${escapeHtml(session.platform || "-")}</span>
              </div>
              <div class="kv-list">
                ${kv("Model", session.deviceModel || "-")}
                ${kv("OS", session.osVersion || "-")}
                ${kv("Uygulama", session.appVersion || "-")}
                ${kv("Locale", session.localeTag || "-")}
                ${kv("Bolge", session.regionCode || "-")}
                ${kv("Baglanti", session.connectionType || "-")}
                ${kv("Cihaz ulkesi", session.countryIso || "-")}
                ${kv("IP ulkesi", session.ipCountryIso || "-")}
                ${kv("Cihaz ID", session.deviceId || "-")}
                ${kv("IP", session.ipAddress || "-")}
                ${kv("Olustu", formatDateTime(session.createdAt))}
                ${kv("Son gorulme", formatDateTime(session.lastSeenAt))}
                ${kv("Revoke", session.revokedAt ? formatDateTime(session.revokedAt) : "-")}
                ${kv("Sebep", session.revokeReason || "-")}
              </div>
            </article>
          `;
        })
        .join("")}
    </div>
  `;
}

function renderChatsTab() {
  if (!state.selectedChats.length) {
    chatsTab.innerHTML = '<div class="empty-note">Sohbet kaydi bulunmuyor.</div>';
    return;
  }

  chatsTab.innerHTML = `
    <div class="chat-layout">
      <div class="chats-list">
        ${state.selectedChats
          .map((chat) => {
            const active = state.selectedChatId === chat.chatId ? "active" : "";
            const peerNames =
              chat.peers?.map((peer) => peer.displayName || peer.phone || peer.id).join(", ") ||
              "Karsi taraf yok";
            return `
              <article class="chat-card ${active}" data-chat-id="${escapeHtml(chat.chatId)}">
                <div class="badge-row">
                  <span class="pill">${escapeHtml(chat.type || "direct")}</span>
                  ${chat.archivedAt ? '<span class="pill">Arsiv</span>' : ""}
                  ${chat.muted ? '<span class="pill">Sessiz</span>' : ""}
                </div>
                <div class="user-title">${escapeHtml(peerNames)}</div>
                <div class="user-subtitle">${escapeHtml(chat.lastMessage?.text || "Son mesaj yok")}</div>
              </article>
            `;
          })
          .join("")}
      </div>
      <div>
        ${
          state.selectedChatId
            ? renderMessagesColumn()
            : '<div class="empty-note">Mesajlari gormek icin bir sohbet sec.</div>'
        }
      </div>
    </div>
  `;

  chatsTab.querySelectorAll("[data-chat-id]").forEach((node) => {
    node.addEventListener("click", () => {
      loadChatMessages(node.dataset.chatId).catch(showInlineError);
    });
  });
}

function renderMessagesColumn() {
  if (!state.selectedMessages.length) {
    return '<div class="empty-note">Mesajlar yukleniyor veya bulunamadi.</div>';
  }

  return `
    <div class="messages-list">
      ${state.selectedMessages
        .map((message) => {
          const attachments = message.attachments || [];
          return `
            <article class="message-card">
              <header>
                <div>
                  <strong>${escapeHtml(message.sender?.displayName || "-")}</strong>
                  <div class="user-subtitle">
                    ${escapeHtml(message.sender?.username ? `@${message.sender.username}` : (message.sender?.phone || ""))}
                  </div>
                </div>
                <div class="user-subtitle">${escapeHtml(formatDateTime(message.createdAt))}</div>
              </header>
              <div class="message-body">${escapeHtml(message.text || "-")}</div>
              ${message.isEdited ? '<div class="user-subtitle">Duzenlendi</div>' : ""}
              ${
                attachments.length
                  ? `<div class="attachment-row">${attachments.map(renderAttachmentChip).join("")}</div>`
                  : ""
              }
            </article>
          `;
        })
        .join("")}
    </div>
  `;
}

function renderMediaTab() {
  if (!state.selectedMedia.length) {
    mediaTab.innerHTML = '<div class="empty-note">Bu kullanicinin medya kaydi bulunmuyor.</div>';
    return;
  }

  mediaTab.innerHTML = `
    <div class="media-grid">
      ${state.selectedMedia
        .map((media) => {
          const preview = renderMediaPreview(media);
          return `
            <article class="media-tile">
              ${preview}
              <div class="media-meta">
                <span class="media-kind">${escapeHtml(media.kind || "file")}</span>
                <strong>${escapeHtml(media.fileName || media.objectKey || "Medya")}</strong>
                <span class="user-subtitle">${escapeHtml(formatDateTime(media.messageCreatedAt))}</span>
                ${
                  media.url
                    ? `<a class="link-button" href="${escapeAttribute(media.url)}" target="_blank" rel="noreferrer">Ac</a>`
                    : `<span class="user-subtitle">Onizleme yok</span>`
                }
              </div>
            </article>
          `;
        })
        .join("")}
    </div>
  `;
}

function renderAttachmentChip(attachment) {
  const preview = renderMediaPreview(attachment);
  const meta = attachment.fileName || attachment.objectKey || attachment.kind || "Ek";
  return `
    <div class="attachment-chip">
      ${preview}
      <div class="user-subtitle">${escapeHtml(meta)}</div>
      ${
        attachment.url
          ? `<a class="link-button" href="${escapeAttribute(attachment.url)}" target="_blank" rel="noreferrer">Dosyayi ac</a>`
          : ""
      }
    </div>
  `;
}

function renderMediaPreview(media) {
  const url = media.url ? escapeAttribute(media.url) : "";
  if (media.kind === "image" && media.url) {
    return `<img src="${url}" alt="" loading="lazy" />`;
  }
  if (media.kind === "video" && media.url) {
    return `<video src="${url}" controls preload="metadata"></video>`;
  }
  return `<div class="empty-note">${escapeHtml((media.kind || "file").toUpperCase())}</div>`;
}

function renderAvatar(url, label, className) {
  if (url) {
    return `<img class="${className}" src="${escapeAttribute(url)}" alt="" />`;
  }
  const initial = (label || "?").trim().charAt(0).toUpperCase() || "?";
  return `<div class="${className} avatar-fallback">${escapeHtml(initial)}</div>`;
}

function renderAvatarInner(url, label) {
  if (url) {
    return `<img src="${escapeAttribute(url)}" alt="" />`;
  }
  const initial = (label || "?").trim().charAt(0).toUpperCase() || "?";
  return `<span>${escapeHtml(initial)}</span>`;
}

function kv(label, value) {
  return `
    <div class="kv-row">
      <strong>${escapeHtml(label)}</strong>
      <span>${escapeHtml(value || "-")}</span>
    </div>
  `;
}

function formatNumber(value) {
  return new Intl.NumberFormat("tr-TR").format(Number(value || 0));
}

function formatDateTime(value) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("tr-TR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(date);
}

function formatPhone(value) {
  if (!value || !value.startsWith("+")) return value || "-";
  const digits = value.replace(/\D+/g, "");
  if (digits.startsWith("90") && digits.length === 12) {
    const national = digits.slice(2);
    return `+90 ${national.slice(0, 3)} ${national.slice(3, 6)} ${national.slice(6, 8)} ${national.slice(8, 10)}`;
  }
  if (digits.startsWith("44") && digits.length === 12) {
    const national = digits.slice(2);
    return `+44 ${national.slice(0, 4)} ${national.slice(4)}`;
  }
  return value;
}

function statusClass(status) {
  if (status === "SUSPENDED") return "status-suspended";
  if (status === "BANNED") return "status-banned";
  return "";
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}

function showInlineError(error) {
  const message = error?.message || "Beklenmeyen bir hata olustu.";
  window.alert(message);
}

async function init() {
  state.token = localStorage.getItem(storageKey);
  renderShell();

  if (!state.token) return;

  try {
    await bootstrapAdmin();
  } catch (error) {
    localStorage.removeItem(storageKey);
    state.token = null;
    renderShell();
    showInlineError(error);
  }
}

init().catch(showInlineError);
