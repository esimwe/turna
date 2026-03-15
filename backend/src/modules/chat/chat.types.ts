export type ChatMessageStatus = "sent" | "delivered" | "read";
export type ChatAttachmentKind = "image" | "video" | "file";

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
  senderId: string;
  text: string;
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
  lastMessage: string;
  lastMessageAt: string | null;
  unreadCount: number;
  peerId: string | null;
  peerAvatarKey: string | null;
  peerUpdatedAt: string | null;
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
