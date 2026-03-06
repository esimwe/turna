export type AppCallType = "audio" | "video";
export type AppCallStatus =
  | "ringing"
  | "accepted"
  | "declined"
  | "missed"
  | "ended"
  | "cancelled";
export type AppCallProvider = "livekit";

export interface CallUser {
  id: string;
  displayName: string;
  avatarKey: string | null;
  updatedAt: string;
}

export interface CallRecord {
  id: string;
  callerId: string;
  calleeId: string;
  type: AppCallType;
  status: AppCallStatus;
  provider: AppCallProvider;
  providerSessionId: string | null;
  roomName: string | null;
  acceptedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  updatedAt: string;
  caller: CallUser;
  callee: CallUser;
}

export interface CallJoinPayload {
  provider: AppCallProvider;
  url: string;
  roomName: string;
  token: string;
  callId: string;
  type: AppCallType;
}

export interface CallHistoryItem {
  id: string;
  type: AppCallType;
  status: AppCallStatus;
  direction: "incoming" | "outgoing";
  createdAt: string;
  acceptedAt: string | null;
  endedAt: string | null;
  durationSeconds: number | null;
  peer: CallUser;
}
