export type ChatMessageStatus = "sent" | "delivered" | "read";
export type ChatAttachmentKind = "image" | "video" | "file";
export type AppChatType = "direct" | "group";
export type ChatMemberRole = "OWNER" | "ADMIN" | "EDITOR" | "MEMBER";
export type ChatPolicyScope = "OWNER_ONLY" | "ADMIN_ONLY" | "EDITOR_ONLY" | "EVERYONE";
export type ChatJoinRequestStatus = "PENDING" | "APPROVED" | "REJECTED";

export interface ChatAttachment {
  id: string;
  objectKey: string;
  kind: ChatAttachmentKind;
  fileName: string | null;
  contentType: string;
  sizeBytes: number;
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
  url: string | null;
}

export interface ChatMessageEditHistoryEntry {
  text: string;
  editedAt: string;
}

export interface ChatMessage {
  id: string;
  chatId: string;
  chatType?: AppChatType | null;
  senderId: string;
  senderDisplayName: string | null;
  text: string;
  systemType: string | null;
  systemPayload: Record<string, unknown> | null;
  createdAt: string;
  status: ChatMessageStatus;
  editedAt: string | null;
  isEdited: boolean;
  editHistory: ChatMessageEditHistoryEntry[];
  attachments: ChatAttachment[];
}

export interface ChatMessagePage {
  items: ChatMessage[];
  hasMore: boolean;
  nextBefore: string | null;
}

export interface SendMessagePayload {
  chatId: string;
  senderId: string;
  text?: string | null;
  attachments?: SendMessageAttachmentInput[];
}

export interface SendMessageAttachmentInput {
  objectKey: string;
  kind: ChatAttachmentKind;
  fileName?: string | null;
  contentType: string;
  sizeBytes?: number | null;
  width?: number | null;
  height?: number | null;
  durationSeconds?: number | null;
}

export interface ChatSummary {
  chatId: string;
  title: string;
  chatType: AppChatType;
  memberPreviewNames: string[];
  lastMessage: string;
  lastMessageAt: string | null;
  unreadCount: number;
  peerId: string | null;
  peerAvatarKey: string | null;
  peerUpdatedAt: string | null;
  groupAvatarUrl: string | null;
  groupDescription: string | null;
  memberCount: number;
  myRole: ChatMemberRole | null;
  isPublic: boolean;
  isMuted: boolean;
  isBlockedByMe: boolean;
  isArchived: boolean;
  isFavorited: boolean;
  isLocked: boolean;
  folderId: string | null;
  folderName: string | null;
}

export interface DirectoryUser {
  id: string;
  displayName: string;
  username: string | null;
  phone: string | null;
  about: string | null;
  avatarKey: string | null;
  updatedAt: string;
}

export interface ChatMemberSummary {
  userId: string;
  displayName: string;
  username: string | null;
  phone: string | null;
  avatarKey: string | null;
  updatedAt: string;
  role: ChatMemberRole;
  canSend: boolean;
  joinedAt: string;
  lastSeenAt: string | null;
  isMuted: boolean;
  mutedUntil: string | null;
  muteReason: string | null;
}

export interface ChatDetail {
  chatId: string;
  chatType: AppChatType;
  title: string;
  memberPreviewNames: string[];
  description: string | null;
  avatarUrl: string | null;
  createdByUserId: string | null;
  memberCount: number;
  myRole: ChatMemberRole | null;
  isPublic: boolean;
  joinApprovalRequired: boolean;
  memberAddPolicy: "OWNER_ONLY" | "ADMIN_ONLY" | "EDITOR_ONLY" | "EVERYONE";
  whoCanSend: ChatPolicyScope;
  whoCanEditInfo: ChatPolicyScope;
  whoCanInvite: ChatPolicyScope;
  whoCanAddMembers: ChatPolicyScope;
  historyVisibleToNewMembers: boolean;
  myCanSend: boolean;
  myIsMuted: boolean;
  myMutedUntil: string | null;
  myMuteReason: string | null;
}

export interface ChatInviteLinkSummary {
  id: string;
  token: string;
  expiresAt: string | null;
  revokedAt: string | null;
  createdAt: string;
}

export interface ChatJoinRequestSummary {
  id: string;
  userId: string;
  displayName: string;
  username: string | null;
  phone: string | null;
  avatarKey: string | null;
  createdAt: string;
  status: ChatJoinRequestStatus;
}

export interface ChatMuteSummary {
  id: string;
  userId: string;
  displayName: string;
  username: string | null;
  avatarKey: string | null;
  reason: string | null;
  mutedUntil: string | null;
  createdAt: string;
}

export interface ChatBanSummary {
  id: string;
  userId: string;
  displayName: string;
  username: string | null;
  avatarKey: string | null;
  reason: string | null;
  createdAt: string;
}
