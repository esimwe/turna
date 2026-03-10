const storageKey = "turna_admin_access_token";

const pageMeta = {
  dashboard: {
    title: "Dashboard",
    subtitle: "Genel ozet, kritik metrikler ve sistem durumu."
  },
  users: {
    title: "Kullanicilar",
    subtitle: "Kullanici listesi, detaylari, sohbetleri, oturumlari ve medyalari."
  },
  contacts: {
    title: "Rehber",
    subtitle: "Tum kullanicilarin senkronladigi rehber kayitlari ve eslesmeler."
  },
  reports: {
    title: "Sikayetler",
    subtitle: "Kullanici ve mesaj sikayetlerini inceleyin."
  },
  chats: {
    title: "Sohbetler",
    subtitle: "Tum sohbetleri ve iclerindeki mesaj akisini goruntuleyin."
  },
  messages: {
    title: "Mesajlar",
    subtitle: "Global mesaj listesi, gonderen ve chat bazli inceleme."
  },
  media: {
    title: "Medya",
    subtitle: "Turna'ya yuklenen tum medya ve dosyalar."
  },
  sessions: {
    title: "Oturumlar",
    subtitle: "Tum cihaz ve session kayitlarini inceleyin."
  },
  calls: {
    title: "Aramalar",
    subtitle: "Sesli ve goruntulu arama kayitlari."
  },
  push: {
    title: "Push",
    subtitle: "Device token, platform ve push cihazi kayitlari."
  },
  otp: {
    title: "OTP / SMS",
    subtitle: "OTP limitleri, provider ve feature flag durumu."
  },
  countryPolicies: {
    title: "Ulke Politikalari",
    subtitle: "Ulke bazli servis kurallarini goruntuleyin."
  },
  featureFlags: {
    title: "Feature Flags",
    subtitle: "Sistem genelindeki ac/kapat anahtarlari."
  },
  auditLogs: {
    title: "Audit Log",
    subtitle: "Admin aksiyonlarinin iz kayitlari."
  },
  admins: {
    title: "Adminler",
    subtitle: "Admin hesaplari ve roller."
  },
  system: {
    title: "Sistem",
    subtitle: "Backend sagligi, Redis, DB ve runtime bilgileri."
  }
};

const state = {
  token: null,
  admin: null,
  currentPage: "dashboard",
  summary: null,

  users: [],
  selectedUser: null,
  selectedSessions: [],
  selectedChats: [],
  selectedMessages: [],
  selectedMedia: [],
  selectedChatId: null,
  userDetailTab: "overview",

  contacts: [],
  reports: [],
  globalChats: [],
  globalMessages: [],
  globalMedia: [],
  globalSessions: [],
  calls: [],
  pushDevices: [],
  otpSettings: null,
  countryPolicies: [],
  featureFlags: [],
  auditLogs: [],
  admins: [],
  systemHealth: null,

  selectedGlobalChatId: null,
  globalChatMessages: []
};

const $ = (selector) => document.querySelector(selector);

const loginView = $("#login-view");
const appView = $("#app-view");
const loginForm = $("#login-form");
const loginError = $("#login-error");
const logoutButton = $("#logout-button");
const adminMeta = $("#admin-meta");
const sidebarNav = $("#sidebar-nav");
const pageTitle = $("#page-title");
const pageSubtitle = $("#page-subtitle");
const pageContent = $("#page-content");

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  loginError.classList.add("hidden");

  try {
    const payload = await api(
      "/api/admin/auth/login",
      {
        method: "POST",
        body: JSON.stringify({
          username: $("#login-username").value.trim(),
          password: $("#login-password").value
        })
      },
      false
    );
    state.token = payload.accessToken;
    localStorage.setItem(storageKey, state.token);
    await bootstrapAdmin();
  } catch (error) {
    loginError.textContent = error?.message || "Giris yapilamadi.";
    loginError.classList.remove("hidden");
  }
});

logoutButton.addEventListener("click", () => {
  state.token = null;
  state.admin = null;
  state.summary = null;
  localStorage.removeItem(storageKey);
  renderShell();
});

sidebarNav.addEventListener("click", (event) => {
  const button = event.target.closest("[data-page]");
  if (!button) return;
  setPage(button.dataset.page).catch(showInlineError);
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
    headers
  });

  if (response.status === 401) {
    state.token = null;
    state.admin = null;
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
    api("/api/admin/dashboard/summary")
  ]);

  state.admin = mePayload.data;
  state.summary = summaryPayload.data;
  renderShell();
  await setPage(state.currentPage || "dashboard", true);
}

async function setPage(page, force = false) {
  if (!pageMeta[page]) return;
  state.currentPage = page;
  renderShell();
  if (force || page !== "users") {
    await ensurePageData(page, force);
  } else if (!state.users.length) {
    await ensurePageData(page, force);
  }
  renderCurrentPage();
}

async function ensurePageData(page, force = false) {
  if (!force) {
    if (page === "users" && state.users.length) return;
    if (page === "contacts" && state.contacts.length) return;
    if (page === "reports" && state.reports.length) return;
    if (page === "chats" && state.globalChats.length) return;
    if (page === "messages" && state.globalMessages.length) return;
    if (page === "media" && state.globalMedia.length) return;
    if (page === "sessions" && state.globalSessions.length) return;
    if (page === "calls" && state.calls.length) return;
    if (page === "push" && state.pushDevices.length) return;
    if (page === "otp" && state.otpSettings) return;
    if (page === "countryPolicies" && state.countryPolicies.length) return;
    if (page === "featureFlags" && state.featureFlags.length) return;
    if (page === "auditLogs" && state.auditLogs.length) return;
    if (page === "admins" && state.admins.length) return;
    if (page === "system" && state.systemHealth) return;
  }

  if (page === "users") return loadUsers("");
  if (page === "contacts") return loadContacts("");
  if (page === "reports") return loadReports();
  if (page === "chats") return loadGlobalChats("");
  if (page === "messages") return loadGlobalMessages("");
  if (page === "media") return loadGlobalMedia("");
  if (page === "sessions") return loadGlobalSessions("");
  if (page === "calls") return loadCalls("");
  if (page === "push") return loadPushDevices("");
  if (page === "otp") return loadOtpSettings();
  if (page === "countryPolicies") return loadCountryPolicies();
  if (page === "featureFlags") return loadFeatureFlags();
  if (page === "auditLogs") return loadAuditLogs();
  if (page === "admins") return loadAdmins("");
  if (page === "system") return loadSystemHealth();
}

async function loadUsers(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/users${search}`);
  state.users = payload.data || [];
  if (state.currentPage === "users") renderCurrentPage();
}

async function loadUser(userId) {
  const [detailPayload, sessionsPayload, chatsPayload, mediaPayload] = await Promise.all([
    api(`/api/admin/users/${userId}`),
    api(`/api/admin/users/${userId}/sessions`),
    api(`/api/admin/users/${userId}/chats`),
    api(`/api/admin/users/${userId}/media`)
  ]);

  state.selectedUser = detailPayload.data;
  state.selectedSessions = sessionsPayload.data || [];
  state.selectedChats = chatsPayload.data || [];
  state.selectedMedia = mediaPayload.data || [];
  state.selectedChatId = null;
  state.selectedMessages = [];
  state.userDetailTab = "overview";
  renderCurrentPage();
}

async function loadUserChatMessages(chatId) {
  state.selectedChatId = chatId;
  renderCurrentPage();
  const payload = await api(`/api/admin/chats/${chatId}/messages`);
  state.selectedMessages = payload.data || [];
  renderCurrentPage();
}

async function loadContacts(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/contacts${search}`);
  state.contacts = payload.data || [];
  if (state.currentPage === "contacts") renderCurrentPage();
}

async function loadReports() {
  const payload = await api("/api/admin/reports");
  state.reports = payload.data || [];
  if (state.currentPage === "reports") renderCurrentPage();
}

async function loadGlobalChats(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/chats${search}`);
  state.globalChats = payload.data || [];
  state.selectedGlobalChatId = null;
  state.globalChatMessages = [];
  if (state.currentPage === "chats") renderCurrentPage();
}

async function loadGlobalChatMessages(chatId) {
  state.selectedGlobalChatId = chatId;
  renderCurrentPage();
  const payload = await api(`/api/admin/chats/${chatId}/messages`);
  state.globalChatMessages = payload.data || [];
  renderCurrentPage();
}

async function loadGlobalMessages(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/messages${search}`);
  state.globalMessages = payload.data || [];
  if (state.currentPage === "messages") renderCurrentPage();
}

async function loadGlobalMedia(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/media${search}`);
  state.globalMedia = payload.data || [];
  if (state.currentPage === "media") renderCurrentPage();
}

async function loadGlobalSessions(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/sessions${search}`);
  state.globalSessions = payload.data || [];
  if (state.currentPage === "sessions") renderCurrentPage();
}

async function loadCalls(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/calls${search}`);
  state.calls = payload.data || [];
  if (state.currentPage === "calls") renderCurrentPage();
}

async function loadPushDevices(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/push/devices${search}`);
  state.pushDevices = payload.data || [];
  if (state.currentPage === "push") renderCurrentPage();
}

async function loadOtpSettings() {
  const payload = await api("/api/admin/otp/settings");
  state.otpSettings = payload.data || null;
  if (state.currentPage === "otp") renderCurrentPage();
}

async function loadCountryPolicies() {
  const payload = await api("/api/admin/country-policies");
  state.countryPolicies = payload.data || [];
  if (state.currentPage === "countryPolicies") renderCurrentPage();
}

async function loadFeatureFlags() {
  const payload = await api("/api/admin/feature-flags");
  state.featureFlags = payload.data || [];
  if (state.currentPage === "featureFlags") renderCurrentPage();
}

async function loadAuditLogs() {
  const payload = await api("/api/admin/audit-logs");
  state.auditLogs = payload.data || [];
  if (state.currentPage === "auditLogs") renderCurrentPage();
}

async function loadAdmins(query) {
  const search = query ? `?q=${encodeURIComponent(query)}` : "";
  const payload = await api(`/api/admin/admins${search}`);
  state.admins = payload.data || [];
  if (state.currentPage === "admins") renderCurrentPage();
}

async function loadSystemHealth() {
  const payload = await api("/api/admin/system/health");
  state.systemHealth = payload.data || null;
  if (state.currentPage === "system") renderCurrentPage();
}

function renderShell() {
  const loggedIn = Boolean(state.token && state.admin);
  loginView.classList.toggle("hidden", loggedIn);
  appView.classList.toggle("hidden", !loggedIn);
  sidebarNav.classList.toggle("hidden", !loggedIn);
  logoutButton.classList.toggle("hidden", !loggedIn);
  adminMeta.classList.toggle("hidden", !loggedIn);

  if (!loggedIn) {
    adminMeta.innerHTML = "";
    pageContent.innerHTML = "";
    return;
  }

  adminMeta.innerHTML = `
    <strong>${escapeHtml(state.admin.displayName || "Admin")}</strong>
    <span>${escapeHtml(state.admin.username || "")}</span>
    <span>${escapeHtml(state.admin.role || "")}</span>
  `;

  const meta = pageMeta[state.currentPage] || pageMeta.dashboard;
  pageTitle.textContent = meta.title;
  pageSubtitle.textContent = meta.subtitle;

  sidebarNav.querySelectorAll("[data-page]").forEach((node) => {
    node.classList.toggle("active", node.dataset.page === state.currentPage);
  });

  renderSummary();
  renderCurrentPage();
}

function renderSummary() {
  const summary = state.summary;
  $("#metric-total-users").textContent = formatNumber(summary?.totalUsers || 0);
  $("#metric-active-sessions").textContent = formatNumber(summary?.activeSessions || 0);
  $("#metric-messages").textContent = formatNumber(summary?.messagesLast24h || 0);
  $("#metric-open-reports").textContent = formatNumber(summary?.openReports || 0);
}

function renderCurrentPage() {
  if (!state.admin) return;

  if (state.currentPage === "dashboard") {
    pageContent.innerHTML = renderDashboardPage();
    return;
  }
  if (state.currentPage === "users") {
    pageContent.innerHTML = renderUsersPage();
    attachUsersPageEvents();
    return;
  }
  if (state.currentPage === "contacts") {
    pageContent.innerHTML = renderContactsPage();
    attachSearchForm("contacts-search-form", "contacts-search-input", loadContacts);
    return;
  }
  if (state.currentPage === "reports") {
    pageContent.innerHTML = renderReportsPage();
    return;
  }
  if (state.currentPage === "chats") {
    pageContent.innerHTML = renderGlobalChatsPage();
    attachSearchForm("global-chats-search-form", "global-chats-search-input", loadGlobalChats);
    pageContent.querySelectorAll("[data-global-chat-id]").forEach((node) => {
      node.addEventListener("click", () => {
        loadGlobalChatMessages(node.dataset.globalChatId).catch(showInlineError);
      });
    });
    return;
  }
  if (state.currentPage === "messages") {
    pageContent.innerHTML = renderMessagesPage();
    attachSearchForm("messages-search-form", "messages-search-input", loadGlobalMessages);
    return;
  }
  if (state.currentPage === "media") {
    pageContent.innerHTML = renderGlobalMediaPage();
    attachSearchForm("media-search-form", "media-search-input", loadGlobalMedia);
    return;
  }
  if (state.currentPage === "sessions") {
    pageContent.innerHTML = renderSessionsPage();
    attachSearchForm("sessions-search-form", "sessions-search-input", loadGlobalSessions);
    return;
  }
  if (state.currentPage === "calls") {
    pageContent.innerHTML = renderCallsPage();
    attachSearchForm("calls-search-form", "calls-search-input", loadCalls);
    return;
  }
  if (state.currentPage === "push") {
    pageContent.innerHTML = renderPushPage();
    attachSearchForm("push-search-form", "push-search-input", loadPushDevices);
    return;
  }
  if (state.currentPage === "otp") {
    pageContent.innerHTML = renderOtpPage();
    return;
  }
  if (state.currentPage === "countryPolicies") {
    pageContent.innerHTML = renderCountryPoliciesPage();
    return;
  }
  if (state.currentPage === "featureFlags") {
    pageContent.innerHTML = renderFeatureFlagsPage();
    return;
  }
  if (state.currentPage === "auditLogs") {
    pageContent.innerHTML = renderAuditLogsPage();
    return;
  }
  if (state.currentPage === "admins") {
    pageContent.innerHTML = renderAdminsPage();
    attachSearchForm("admins-search-form", "admins-search-input", loadAdmins);
    return;
  }
  if (state.currentPage === "system") {
    pageContent.innerHTML = renderSystemPage();
  }
}

function renderDashboardPage() {
  const summary = state.summary || {};
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Genel ozet</h2>
          <p>Turna operasyonunun anlik durumu.</p>
        </div>
      </div>
      <div class="overview-grid">
        ${renderInfoCard("Kullanicilar", [
          kv("Toplam", formatNumber(summary.totalUsers || 0)),
          kv("Aktif", formatNumber(summary.activeUsers || 0)),
          kv("Suspended", formatNumber(summary.suspendedUsers || 0)),
          kv("Banned", formatNumber(summary.bannedUsers || 0))
        ])}
        ${renderInfoCard("Iletisim", [
          kv("Toplam sohbet", formatNumber(summary.totalChats || 0)),
          kv("24s mesaj", formatNumber(summary.messagesLast24h || 0)),
          kv("24s arama", formatNumber(summary.callsLast24h || 0)),
          kv("Acik sikayet", formatNumber(summary.openReports || 0))
        ])}
        ${renderInfoCard("Session & Push", [
          kv("Aktif session", formatNumber(summary.activeSessions || 0)),
          kv("Aktif device token", formatNumber(summary.activeDeviceTokens || 0)),
          kv("Feature flag", formatNumber(summary.enabledFeatureFlags || 0)),
          kv("Ulke policy", formatNumber(summary.countryPolicyCount || 0))
        ])}
        ${renderInfoCard("Hizli not", [
          kv("Panel durumu", "Hazir"),
          kv("Admin rolu", state.admin?.role || "-"),
          kv("Kullanici detay", "Aktif"),
          kv("Rehber/Medya", "Aktif")
        ])}
      </div>
    </section>
  `;
}

function renderUsersPage() {
  return `
    <section class="workspace">
      <section class="panel users-panel">
        <div class="panel-heading">
          <div>
            <h2>Kullanicilar</h2>
            <p>Arama yap, sec ve detaylarini incele.</p>
          </div>
          <form id="users-search-form" class="search-form">
            <input id="users-search-input" type="search" placeholder="Ad, @username, telefon, email" />
            <button class="ghost-button" type="submit">Ara</button>
          </form>
        </div>
        <div class="users-list">
          ${state.users.length ? state.users.map(renderUserCard).join("") : '<div class="empty-note">Kullanici bulunamadi.</div>'}
        </div>
      </section>

      <section class="panel detail-panel">
        ${
          state.selectedUser
            ? renderSelectedUserDetail()
            : '<div class="state-empty">Listeden bir kullanici sec.</div>'
        }
      </section>
    </section>
  `;
}

function renderSelectedUserDetail() {
  const user = state.selectedUser;
  return `
    <header class="detail-header">
      <div class="detail-identity">
        <div class="avatar-shell">${renderAvatarInner(user.avatarUrl, user.displayName)}</div>
        <div>
          <h2>${escapeHtml(user.displayName || "-")}</h2>
          <div class="muted-text">
            ${[user.username ? `@${user.username}` : null, user.phone ? formatPhone(user.phone) : null, user.email || null]
              .filter(Boolean)
              .map(escapeHtml)
              .join(" • ")}
          </div>
        </div>
      </div>
      <div class="badge-row">
        <span class="status-badge ${statusClass(user.accountStatus)}">${escapeHtml(user.accountStatus || "-")}</span>
        <span class="soft-badge">${user.lastSeenAt ? `Son gorulme ${escapeHtml(formatDateTime(user.lastSeenAt))}` : "Son gorulme yok"}</span>
      </div>
    </header>

    <nav class="tab-row">
      <button class="tab-button ${state.userDetailTab === "overview" ? "active" : ""}" data-user-tab="overview" type="button">Genel</button>
      <button class="tab-button ${state.userDetailTab === "sessions" ? "active" : ""}" data-user-tab="sessions" type="button">Oturumlar</button>
      <button class="tab-button ${state.userDetailTab === "chats" ? "active" : ""}" data-user-tab="chats" type="button">Sohbetler</button>
      <button class="tab-button ${state.userDetailTab === "media" ? "active" : ""}" data-user-tab="media" type="button">Medya</button>
    </nav>

    ${state.userDetailTab === "overview" ? renderUserOverviewTab() : ""}
    ${state.userDetailTab === "sessions" ? renderUserSessionsTab() : ""}
    ${state.userDetailTab === "chats" ? renderUserChatsTab() : ""}
    ${state.userDetailTab === "media" ? renderUserMediaTab() : ""}
  `;
}

function renderUserOverviewTab() {
  const user = state.selectedUser;
  const latest = user.latestSession || state.selectedSessions[0] || null;
  return `
    <div class="overview-grid">
      ${renderInfoCard("Profil", [
        kv("Kullanici ID", user.id),
        kv("Telefon", user.phone ? formatPhone(user.phone) : "-"),
        kv("Email", user.email || "-"),
        kv("Bio", user.about || "-"),
        kv("Olusturulma", formatDateTime(user.createdAt)),
        kv("Onboarding", user.onboardingCompletedAt ? "Tamamlandi" : "Bekliyor")
      ])}
      ${renderInfoCard("Sayilar", [
        kv("Sohbet", formatNumber(user._count?.memberships || 0)),
        kv("Mesaj", formatNumber(user._count?.messages || 0)),
        kv("Cihaz token", formatNumber(user._count?.devices || 0)),
        kv("Tum session", formatNumber(user._count?.authSessions || 0)),
        kv("Aktif session", formatNumber(user.activeSessionCount || 0)),
        kv("Sikayet", formatNumber(user._count?.reportsAgainst || 0))
      ])}
      ${renderInfoCard("Son cihaz", [
        kv("Model", latest?.deviceModel || "-"),
        kv("Platform", latest?.platform || "-"),
        kv("OS", latest?.osVersion || "-"),
        kv("Uygulama", latest?.appVersion || "-"),
        kv("Dil", latest?.localeTag || "-"),
        kv("Bolge", latest?.regionCode || "-"),
        kv("Baglanti", latest?.connectionType || "-"),
        kv("Cihaz ulkesi", latest?.countryIso || "-"),
        kv("IP ulkesi", latest?.ipCountryIso || "-")
      ])}
      ${renderInfoCard("Erisim", [
        kv("Hesap", user.accountStatus || "-"),
        kv("Durum nedeni", user.accountStatusReason || "-"),
        kv("OTP", user.otpBlocked ? "Bloklu" : "Acik"),
        kv("Mesaj", user.sendRestricted ? "Kisitli" : "Serbest"),
        kv("Arama", user.callRestricted ? "Kisitli" : "Serbest")
      ])}
    </div>
  `;
}

function renderUserSessionsTab() {
  if (!state.selectedSessions.length) {
    return '<div class="empty-note">Oturum kaydi bulunmuyor.</div>';
  }

  return `
    <div class="sessions-table">
      ${state.selectedSessions
        .map(
          (session) => `
            <article class="session-card ${session.revokedAt ? "" : "active"}">
              <div class="kv-list">
                ${kv("Platform", session.platform || "-")}
                ${kv("Model", session.deviceModel || "-")}
                ${kv("OS", session.osVersion || "-")}
                ${kv("App", session.appVersion || "-")}
                ${kv("Locale", session.localeTag || "-")}
                ${kv("Baglanti", session.connectionType || "-")}
                ${kv("Cihaz ulkesi", session.countryIso || "-")}
                ${kv("IP ulkesi", session.ipCountryIso || "-")}
                ${kv("IP", session.ipAddress || "-")}
                ${kv("Olusturulma", formatDateTime(session.createdAt))}
                ${kv("Son gorulme", formatDateTime(session.lastSeenAt))}
                ${kv("Revoked", session.revokedAt ? formatDateTime(session.revokedAt) : "Aktif")}
              </div>
            </article>
          `
        )
        .join("")}
    </div>
  `;
}

function renderUserChatsTab() {
  return `
    <div class="chat-layout">
      <div class="chats-list">
        ${
          state.selectedChats.length
            ? state.selectedChats
                .map(
                  (chat) => `
                    <article class="chat-card ${state.selectedChatId === chat.chatId ? "active" : ""}" data-user-chat-id="${escapeAttribute(chat.chatId)}">
                      <div class="user-title">${escapeHtml(chat.peers?.map((peer) => peer.displayName || peer.phone || peer.username || "Kullanici").join(", ") || "Sohbet")}</div>
                      <div class="user-subtitle">${escapeHtml(chat.lastMessage?.text || "Son mesaj yok")}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Sohbet bulunmuyor.</div>'
        }
      </div>
      <div>
        ${
          state.selectedChatId
            ? renderMessagesColumn(state.selectedMessages)
            : '<div class="empty-note">Mesajlari gormek icin bir sohbet sec.</div>'
        }
      </div>
    </div>
  `;
}

function renderUserMediaTab() {
  return renderMediaGallery(state.selectedMedia, "Bu kullanicinin medya kaydi bulunmuyor.");
}

function renderContactsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Rehber</h2>
          <p>Tum kullanicilarin sunucuya senkronladigi rehber kayitlari.</p>
        </div>
        <form id="contacts-search-form" class="search-form">
          <input id="contacts-search-input" type="search" placeholder="Owner, rehber adi veya numara" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      <div class="table-list">
        ${
          state.contacts.length
            ? state.contacts
                .map(
                  (row) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(row.displayName || "-")}</strong>
                        <span class="soft-badge">${escapeHtml(row.lookupKey || "-")}</span>
                      </div>
                      <div class="user-subtitle">Owner: ${escapeHtml(row.owner?.displayName || "-")} ${row.owner?.username ? `(@${escapeHtml(row.owner.username)})` : ""}</div>
                      <div class="user-subtitle">Owner telefon: ${escapeHtml(formatPhone(row.owner?.phone || ""))}</div>
                      <div class="user-subtitle">Son sync: ${escapeHtml(formatDateTime(row.updatedAt))}</div>
                      ${
                        row.matchedUser
                          ? `<div class="badge-row"><span class="status-badge">Eslesen Turna kullanicisi</span><span class="pill">${escapeHtml(row.matchedUser.displayName || row.matchedUser.phone || "-")}</span></div>`
                          : `<div class="badge-row"><span class="pill">Eslesme yok</span></div>`
                      }
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Rehber kaydi bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderReportsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Sikayetler</h2>
          <p>Kullanici ve mesaj sikayetleri.</p>
        </div>
      </div>
      <div class="table-list">
        ${
          state.reports.length
            ? state.reports
                .map(
                  (report) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(report.reasonCode || "-")}</strong>
                        <span class="status-badge ${report.status === "OPEN" ? "" : "status-suspended"}">${escapeHtml(report.status || "-")}</span>
                      </div>
                      <div class="user-subtitle">Tip: ${escapeHtml(report.targetType || "-")}</div>
                      <div class="user-subtitle">Reporter: ${escapeHtml(report.reporterUser?.displayName || report.reporterUser?.phone || "-")}</div>
                      <div class="user-subtitle">Olusturulma: ${escapeHtml(formatDateTime(report.createdAt))}</div>
                      <div class="message-body">${escapeHtml(report.details || "-")}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Sikayet bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderGlobalChatsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Sohbetler</h2>
          <p>Tum sohbetler ve secilen sohbetin mesaj akisi.</p>
        </div>
        <form id="global-chats-search-form" class="search-form">
          <input id="global-chats-search-input" type="search" placeholder="Sohbet arama" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      <div class="chat-layout">
        <div class="chats-list">
          ${
            state.globalChats.length
              ? state.globalChats
                  .map(
                    (chat) => `
                      <article class="chat-card ${state.selectedGlobalChatId === chat.id ? "active" : ""}" data-global-chat-id="${escapeAttribute(chat.id)}">
                        <div class="user-title">${escapeHtml(chat.members.map((member) => member.displayName || member.phone || member.username || "Kullanici").join(", "))}</div>
                        <div class="user-subtitle">${escapeHtml(chat.lastMessage?.text || "Son mesaj yok")}</div>
                        <div class="user-subtitle">${escapeHtml(formatDateTime(chat.createdAt))}</div>
                      </article>
                    `
                  )
                  .join("")
              : '<div class="empty-note">Sohbet bulunmuyor.</div>'
          }
        </div>
        <div>
          ${
            state.selectedGlobalChatId
              ? renderMessagesColumn(state.globalChatMessages)
              : '<div class="empty-note">Mesajlari gormek icin bir sohbet sec.</div>'
          }
        </div>
      </div>
    </section>
  `;
}

function renderMessagesPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Mesajlar</h2>
          <p>Global mesaj listesi.</p>
        </div>
        <form id="messages-search-form" class="search-form">
          <input id="messages-search-input" type="search" placeholder="Metin, ad, @username, telefon" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      ${renderMessagesColumn(state.globalMessages, true)}
    </section>
  `;
}

function renderGlobalMediaPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Medya</h2>
          <p>Turna'ya yuklenen tum medya ve dosyalar.</p>
        </div>
        <form id="media-search-form" class="search-form">
          <input id="media-search-input" type="search" placeholder="Dosya adi, object key, kullanici" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      ${renderMediaGallery(state.globalMedia, "Medya bulunmuyor.", false)}
    </section>
  `;
}

function renderSessionsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Oturumlar & Cihazlar</h2>
          <p>Tum session ve cihaz kayitlari.</p>
        </div>
        <form id="sessions-search-form" class="search-form">
          <input id="sessions-search-input" type="search" placeholder="Kullanici, cihaz modeli, IP" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      <div class="sessions-table">
        ${
          state.globalSessions.length
            ? state.globalSessions
                .map(
                  (session) => `
                    <article class="session-card ${session.revokedAt ? "" : "active"}">
                      <div class="list-title-row">
                        <strong>${escapeHtml(session.user?.displayName || session.user?.phone || "-")}</strong>
                        <span class="soft-badge">${escapeHtml(session.platform || "-")}</span>
                      </div>
                      <div class="kv-list">
                        ${kv("Model", session.deviceModel || "-")}
                        ${kv("OS", session.osVersion || "-")}
                        ${kv("App", session.appVersion || "-")}
                        ${kv("Locale", session.localeTag || "-")}
                        ${kv("Baglanti", session.connectionType || "-")}
                        ${kv("Cihaz ulkesi", session.countryIso || "-")}
                        ${kv("IP ulkesi", session.ipCountryIso || "-")}
                        ${kv("IP", session.ipAddress || "-")}
                        ${kv("Son gorulme", formatDateTime(session.lastSeenAt))}
                      </div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Session bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderCallsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Aramalar</h2>
          <p>Sesli ve goruntulu arama kayitlari.</p>
        </div>
        <form id="calls-search-form" class="search-form">
          <input id="calls-search-input" type="search" placeholder="Caller, callee, telefon" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      <div class="table-list">
        ${
          state.calls.length
            ? state.calls
                .map(
                  (call) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(call.caller?.displayName || call.caller?.phone || "-")} → ${escapeHtml(call.callee?.displayName || call.callee?.phone || "-")}</strong>
                        <span class="soft-badge">${escapeHtml(call.type || "-")}</span>
                      </div>
                      <div class="badge-row">
                        <span class="status-badge ${call.status === "accepted" ? "" : "status-suspended"}">${escapeHtml(call.status || "-")}</span>
                        <span class="pill">${escapeHtml(call.provider || "-")}</span>
                      </div>
                      <div class="user-subtitle">Olusturulma: ${escapeHtml(formatDateTime(call.createdAt))}</div>
                      <div class="user-subtitle">Accepted: ${escapeHtml(formatDateTime(call.acceptedAt))}</div>
                      <div class="user-subtitle">Ended: ${escapeHtml(formatDateTime(call.endedAt))}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Arama kaydi bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderPushPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Push Cihazlari</h2>
          <p>Standart ve VoIP token kayitlari.</p>
        </div>
        <form id="push-search-form" class="search-form">
          <input id="push-search-input" type="search" placeholder="Kullanici, token, cihaz etiketi" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      <div class="table-list">
        ${
          state.pushDevices.length
            ? state.pushDevices
                .map(
                  (device) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(device.user?.displayName || device.user?.phone || "-")}</strong>
                        <span class="soft-badge">${escapeHtml(device.platform || "-")}</span>
                      </div>
                      <div class="badge-row">
                        <span class="pill">${escapeHtml(device.tokenKind || "-")}</span>
                        <span class="pill">${device.isActive ? "Aktif" : "Pasif"}</span>
                      </div>
                      <div class="user-subtitle">Etiket: ${escapeHtml(device.deviceLabel || "-")}</div>
                      <div class="user-subtitle">Token: ${escapeHtml(device.tokenPreview || "-")}</div>
                      <div class="user-subtitle">Guncelleme: ${escapeHtml(formatDateTime(device.updatedAt))}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Push cihazi bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderOtpPage() {
  const otp = state.otpSettings;
  if (!otp) {
    return '<section class="panel page-panel"><div class="empty-note">OTP ayarlari yuklenemedi.</div></section>';
  }

  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>OTP / SMS</h2>
          <p>Provider, sabit OTP ve limitler.</p>
        </div>
      </div>
      <div class="overview-grid">
        ${renderInfoCard("Genel", [
          kv("Provider", otp.provider || "-"),
          kv("Fixed OTP", otp.fixedOtpCodeEnabled ? "Aktif" : "Kapali"),
          kv("OTP login", otp.otpLoginEnabled ? "Acik" : "Kapali"),
          kv("Phone change", otp.phoneChangeEnabled ? "Acik" : "Kapali")
        ])}
        ${renderInfoCard("Sureler", [
          kv("TTL", `${otp.ttlSeconds} sn`),
          kv("Cooldown", `${otp.resendCooldownSeconds} sn`),
          kv("Max deneme", formatNumber(otp.maxAttempts)),
          kv("Phone 10m", formatNumber(otp.phoneLimit10m))
        ])}
        ${renderInfoCard("Limitler", [
          kv("Phone 24h", formatNumber(otp.phoneLimit24h)),
          kv("IP 10m", formatNumber(otp.ipLimit10m)),
          kv("IP 24h", formatNumber(otp.ipLimit24h)),
          kv("Durum", "Calisiyor")
        ])}
      </div>
    </section>
  `;
}

function renderCountryPoliciesPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Ulke Politikalari</h2>
          <p>Ulke bazli servis ayarlari.</p>
        </div>
      </div>
      <div class="table-list">
        ${
          state.countryPolicies.length
            ? state.countryPolicies
                .map(
                  (policy) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(policy.countryName || "-")} (${escapeHtml(policy.countryIso || "-")})</strong>
                        <span class="soft-badge">${escapeHtml(policy.smsProvider || "-")}</span>
                      </div>
                      <div class="badge-row">
                        <span class="pill">${policy.isServiceEnabled ? "Servis acik" : "Servis kapali"}</span>
                        <span class="pill">${policy.isOtpEnabled ? "OTP acik" : "OTP kapali"}</span>
                        <span class="pill">${policy.isMessagingEnabled ? "Mesaj acik" : "Mesaj kapali"}</span>
                        <span class="pill">${policy.isCallingEnabled ? "Arama acik" : "Arama kapali"}</span>
                      </div>
                      <div class="user-subtitle">Dial code: ${escapeHtml(policy.dialCode || "-")}</div>
                      <div class="user-subtitle">Guncelleme: ${escapeHtml(formatDateTime(policy.updatedAt))}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Ulke policy bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderFeatureFlagsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Feature Flags</h2>
          <p>Sistem genelindeki ac/kapat anahtarlari.</p>
        </div>
      </div>
      <div class="table-list">
        ${
          state.featureFlags.length
            ? state.featureFlags
                .map(
                  (flag) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(flag.key || "-")}</strong>
                        <span class="status-badge ${flag.enabled ? "" : "status-suspended"}">${flag.enabled ? "Aktif" : "Pasif"}</span>
                      </div>
                      <div class="message-body">${escapeHtml(flag.description || "-")}</div>
                      <div class="user-subtitle">Guncelleme: ${escapeHtml(formatDateTime(flag.updatedAt))}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Feature flag bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderAuditLogsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Audit Log</h2>
          <p>Admin aksiyon kayitlari.</p>
        </div>
      </div>
      <div class="table-list">
        ${
          state.auditLogs.length
            ? state.auditLogs
                .map(
                  (log) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(log.action || "-")}</strong>
                        <span class="soft-badge">${escapeHtml(formatDateTime(log.createdAt))}</span>
                      </div>
                      <div class="user-subtitle">Admin: ${escapeHtml(log.actorAdmin?.displayName || "-")} (${escapeHtml(log.actorAdmin?.role || "-")})</div>
                      <div class="user-subtitle">Target: ${escapeHtml(log.targetType || "-")} ${escapeHtml(log.targetId || "-")}</div>
                      <div class="message-body">${escapeHtml(log.reason || "-")}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Audit log bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderAdminsPage() {
  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Adminler</h2>
          <p>Admin hesaplari ve roller.</p>
        </div>
        <form id="admins-search-form" class="search-form">
          <input id="admins-search-input" type="search" placeholder="Admin ara" />
          <button class="ghost-button" type="submit">Ara</button>
        </form>
      </div>
      <div class="table-list">
        ${
          state.admins.length
            ? state.admins
                .map(
                  (admin) => `
                    <article class="list-card">
                      <div class="list-title-row">
                        <strong>${escapeHtml(admin.displayName || "-")}</strong>
                        <span class="soft-badge">${escapeHtml(admin.role || "-")}</span>
                      </div>
                      <div class="user-subtitle">@${escapeHtml(admin.username || "-")}</div>
                      <div class="user-subtitle">Son login: ${escapeHtml(formatDateTime(admin.lastLoginAt))}</div>
                      <div class="user-subtitle">Olusturulma: ${escapeHtml(formatDateTime(admin.createdAt))}</div>
                    </article>
                  `
                )
                .join("")
            : '<div class="empty-note">Admin bulunmuyor.</div>'
        }
      </div>
    </section>
  `;
}

function renderSystemPage() {
  const system = state.systemHealth;
  if (!system) {
    return '<section class="panel page-panel"><div class="empty-note">Sistem bilgisi yuklenemedi.</div></section>';
  }

  return `
    <section class="panel page-panel">
      <div class="panel-heading">
        <div>
          <h2>Sistem</h2>
          <p>Backend runtime ve servis sagligi.</p>
        </div>
      </div>
      <div class="overview-grid">
        ${renderInfoCard("Runtime", [
          kv("Node", system.nodeVersion || "-"),
          kv("Env", system.environment || "-"),
          kv("Uptime", `${formatNumber(system.uptimeSeconds || 0)} sn`),
          kv("SMS", system.smsProvider || "-")
        ])}
        ${renderInfoCard("Saglik", [
          kv("Database", system.databaseStatus || "-"),
          kv("Redis", system.redisStatus || "-"),
          kv("Fixed OTP", system.fixedOtpCodeEnabled ? "Aktif" : "Kapali"),
          kv("Panel", "Calisiyor")
        ])}
      </div>
    </section>
  `;
}

function renderMessagesColumn(messages, showChatMeta = false) {
  if (!messages.length) {
    return '<div class="empty-note">Mesaj bulunmuyor.</div>';
  }

  return `
    <div class="messages-list">
      ${messages
        .map(
          (message) => `
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
              ${showChatMeta ? `<div class="user-subtitle">Chat: ${escapeHtml(message.chatId || "-")}</div>` : ""}
              <div class="message-body">${escapeHtml(message.text || "-")}</div>
              ${message.isEdited || message.editedAt ? '<div class="user-subtitle">Duzenlendi</div>' : ""}
              ${
                (message.attachments || []).length
                  ? `<div class="attachment-row">${(message.attachments || []).map(renderAttachmentChip).join("")}</div>`
                  : ""
              }
            </article>
          `
        )
        .join("")}
    </div>
  `;
}

function renderMediaGallery(items, emptyLabel, includeDirections = true) {
  if (!items.length) {
    return `<div class="empty-note">${escapeHtml(emptyLabel)}</div>`;
  }

  const outgoingCount = includeDirections ? items.filter((item) => item.isOutgoing).length : 0;
  const incomingCount = includeDirections ? items.length - outgoingCount : 0;

  return `
    ${includeDirections ? `<div class="badge-row media-summary-row"><span class="soft-badge">Toplam ${formatNumber(items.length)}</span><span class="soft-badge">Gonderilen ${formatNumber(outgoingCount)}</span><span class="soft-badge">Gelen ${formatNumber(incomingCount)}</span></div>` : ""}
    <div class="media-grid">
      ${items
        .map((media) => {
          const preview = renderMediaPreview(media);
          const senderLine = media.sender
            ? `${escapeHtml(media.sender.displayName || media.sender.username || formatPhone(media.sender.phone || "") || "Kullanici")} tarafindan gonderildi`
            : "";
          return `
            <article class="media-tile ${includeDirections ? (media.isOutgoing ? "media-tile-outgoing" : "media-tile-incoming") : ""}">
              ${preview}
              <div class="media-meta">
                <div class="badge-row">
                  ${
                    includeDirections
                      ? `<span class="pill ${media.isOutgoing ? "media-direction-outgoing" : "media-direction-incoming"}">${media.isOutgoing ? "Gonderilen" : "Gelen"}</span>`
                      : ""
                  }
                  <span class="media-kind">${escapeHtml(media.kind || "file")}</span>
                </div>
                <strong>${escapeHtml(media.fileName || media.objectKey || "Medya")}</strong>
                ${senderLine ? `<span class="user-subtitle">${senderLine}</span>` : ""}
                <span class="user-subtitle">${escapeHtml(formatDateTime(media.messageCreatedAt || media.createdAt))}</span>
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
  const contentType = String(media.contentType || "").toLowerCase();
  const isImage = media.kind === "image" || contentType.startsWith("image/");
  const isVideo = media.kind === "video" || contentType.startsWith("video/");

  if (isImage && media.url) {
    return `<img src="${url}" alt="" loading="lazy" />`;
  }
  if (isVideo && media.url) {
    return `<video src="${url}" controls preload="metadata"></video>`;
  }
  if (contentType.startsWith("audio/")) {
    return `<div class="empty-note">SES</div>`;
  }
  return `<div class="empty-note">${escapeHtml((media.kind || "file").toUpperCase())}</div>`;
}

function renderInfoCard(title, items) {
  return `
    <article class="info-card">
      <h3>${escapeHtml(title)}</h3>
      <div class="kv-list">${items.join("")}</div>
    </article>
  `;
}

function renderUserCard(user) {
  const active = state.selectedUser?.id === user.id ? "active" : "";
  const phone = user.phone ? formatPhone(user.phone) : "Telefon yok";
  return `
    <article class="user-card ${active}" data-user-id="${escapeAttribute(user.id)}">
      <div class="user-card-head">
        ${renderAvatar(user.avatarUrl, user.displayName, "avatar")}
        <div>
          <div class="user-title">${escapeHtml(user.displayName || "-")}</div>
          <div class="user-subtitle">${escapeHtml(user.username ? `@${user.username}` : phone)}</div>
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
}

function attachUsersPageEvents() {
  attachSearchForm("users-search-form", "users-search-input", loadUsers);

  pageContent.querySelectorAll("[data-user-id]").forEach((node) => {
    node.addEventListener("click", () => {
      loadUser(node.dataset.userId).catch(showInlineError);
    });
  });

  pageContent.querySelectorAll("[data-user-tab]").forEach((node) => {
    node.addEventListener("click", () => {
      state.userDetailTab = node.dataset.userTab;
      renderCurrentPage();
    });
  });

  pageContent.querySelectorAll("[data-user-chat-id]").forEach((node) => {
    node.addEventListener("click", () => {
      loadUserChatMessages(node.dataset.userChatId).catch(showInlineError);
    });
  });
}

function attachSearchForm(formId, inputId, loader) {
  const form = document.getElementById(formId);
  const input = document.getElementById(inputId);
  if (!form || !input) return;

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    loader(input.value.trim()).catch(showInlineError);
  });
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
  return new Intl.DateTimeFormat("tr-TR", { dateStyle: "short", timeStyle: "short" }).format(date);
}

function formatPhone(value) {
  if (!value) return "-";
  if (!value.startsWith("+")) return value;
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
  if (status === "SUSPENDED" || status === "UNDER_REVIEW") return "status-suspended";
  if (status === "BANNED" || status === "REJECTED") return "status-banned";
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
  window.alert(error?.message || "Beklenmeyen bir hata olustu.");
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
