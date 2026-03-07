import type { AppCallProvider, AppCallType, CallJoinPayload } from "./call.types.js";

export interface CreateCallSessionInput {
  callId: string;
  type: AppCallType;
  callerId: string;
  calleeId: string;
}

export interface CreateCallSessionResult {
  provider: AppCallProvider;
  sessionId: string;
  roomName: string;
}

export interface CreateCallParticipantTokenInput {
  callId: string;
  roomName: string;
  type: AppCallType;
  userId: string;
  participantName: string;
}

export interface CloseCallSessionInput {
  callId: string;
  sessionId?: string | null;
  roomName?: string | null;
}

export interface CallProvider {
  readonly name: AppCallProvider;
  isConfigured(): boolean;
  createSession(input: CreateCallSessionInput): Promise<CreateCallSessionResult>;
  createParticipantToken(input: CreateCallParticipantTokenInput): Promise<CallJoinPayload>;
  closeSession(input: CloseCallSessionInput): Promise<void>;
  getParticipantCount(input: CloseCallSessionInput): Promise<number | null>;
}
