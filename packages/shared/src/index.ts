/**
 * @deprecated 레거시 TypeScript 계약 참조용.
 * SSOT: apps/api/app/schemas/ (Pydantic) → scripts/openapi.json → Flutter codegen.
 * 신규·변경 필드는 schema에 추가하고 export/codegen 흐름을 따른다.
 */
export type BotType = "character" | "utility";
export type BotStatus = "draft" | "published";
export type BotRating = "all" | "adult";
export type MessageRole = "user" | "assistant" | "system";

export interface User {
  id: string;
  email: string;
  displayName?: string;
  isAdmin?: boolean;
  createdAt?: string;
}

export interface Bot {
  id: string;
  creatorId: string;
  type: BotType;
  status: BotStatus;
  title: string;
  shortIntro?: string;
  thumbnailUrl?: string;
  tags: string[];
  rating: BotRating;
  model: string;
  createdAt: string;
  updatedAt: string;
}

export interface SupportingCastMember {
  name: string;
  blurb: string;
}

export interface CharacterContent {
  name: string;
  personality: string;
  background?: string;
  greeting: string;
  userRole?: string;
  scenario?: string;
  conversationRules?: string;
  supportingCast?: SupportingCastMember[];
}

export interface UtilityContent {
  systemPrompt: string;
  knowledgeText?: string;
}

export interface CharacterStudioWorldPrefs {
  genre: string;
  era?: string;
  mood: number;
  ruleLine?: string;
}

export interface CharacterStudioUserPrefs {
  rolePreset: string;
  relationToMain: string;
  customLine?: string;
}

export interface CharacterStudioMainPrefs {
  name?: string;
  gender?: string;
  /** 이름 스타일 프리셋 id (korean, japanese, …) */
  nameStyle?: string;
  tone: number;
  speechLength: number;
  conceptLine?: string;
  relation?: string;
}

export interface CharacterStudioStartPrefs {
  openingPreset: string;
  customOpening?: string;
}

export interface CharacterStudioRulesPrefs {
  speechLength: number;
  ruleTags: string[];
}

export interface CharacterStudioPrefs {
  world: CharacterStudioWorldPrefs;
  start: CharacterStudioStartPrefs;
  user: CharacterStudioUserPrefs;
  mains: CharacterStudioMainPrefs[];
  /** @deprecated legacy single-main drafts; migrated to `mains` on read */
  main?: CharacterStudioMainPrefs;
  rules: CharacterStudioRulesPrefs;
  supporting: SupportingCastMember[];
  /** 시리즈 공통 이름 스타일 (korean, japanese, …) */
  nameStyle?: string;
  /** 배경 캐릭터 슬롯 수 (0~3) */
  supportingCount?: number;
}

export interface UtilityStudioPrefs {
  rolePreset: string;
  tone: number;
  detailLevel: number;
  customLine?: string;
}

export interface BotDetail extends Bot {
  content: CharacterContent | UtilityContent;
  draftPrefs?: CharacterStudioPrefs | UtilityStudioPrefs;
}

export interface CreateBotRequest {
  type: BotType;
  title?: string;
  draftPrefs?: CharacterStudioPrefs | UtilityStudioPrefs;
  contentJson?: CharacterContent | UtilityContent;
}

export interface UpdateBotRequest {
  title?: string;
  shortIntro?: string;
  thumbnailUrl?: string;
  tags?: string[];
  rating?: BotRating;
  model?: string;
  contentJson?: CharacterContent | UtilityContent;
  draftPrefs?: CharacterStudioPrefs | UtilityStudioPrefs;
}

export interface PreviewBotRequest {
  type: BotType;
  draftPrefs: CharacterStudioPrefs | UtilityStudioPrefs;
  mainName?: string;
}

export interface PreviewBotResponse {
  content: CharacterContent | UtilityContent;
}

export interface EnrichBotRequest {
  locks?: string[];
  supportingCount?: number;
}

export interface EnrichBotResponse {
  draftPrefs: CharacterStudioPrefs;
  content: CharacterContent;
  enrichedBy: "llm" | "fallback";
  warning?: string;
}

export interface ChatSession {
  id: string;
  botId: string;
  botTitle?: string;
  userId?: string;
  visitorId?: string;
  model?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Message {
  id: string;
  sessionId: string;
  role: MessageRole;
  content: string;
  createdAt: string;
}

export interface ChatRequest {
  botId: string;
  sessionId?: string | null;
  message: string;
  visitorId?: string;
  model?: string;
}

export interface ChatModelItem {
  id: string;
  label: string;
  installed: boolean;
}

export interface ChatResponse {
  sessionId: string;
  reply: string;
  messageId: string;
  model: string;
}

export interface AuthTokenResponse {
  accessToken: string;
  tokenType: string;
}

export interface RegisterRequest {
  email: string;
  password: string;
  displayName?: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export type EpisodeStatus = "draft" | "published";
export type CreditTransactionType = "grant" | "debit" | "refund";

export interface EpisodeSummary {
  id: string;
  botId: string;
  number: number;
  title: string;
  status: EpisodeStatus;
  creditCost: number;
  wordCount: number;
  locked: boolean;
  unlocked: boolean;
  createdAt: string;
}

export interface EpisodeDetail extends EpisodeSummary {
  body?: string;
  summary?: string;
}

export interface EpisodeUnlockResponse {
  episodeId: string;
  unlocked: boolean;
  balance: number;
  creditsSpent: number;
}

export interface CreditBalance {
  balance: number;
}

export interface AdminCreditGrantRequest {
  amount: number;
  note?: string;
}

export interface AdminCreditGrantResponse {
  userId: string;
  balance: number;
  granted: number;
}

export interface GenerateEpisodeRequest {
  publish?: boolean;
}

export interface GenerateEpisodeResponse {
  episode: EpisodeSummary;
}
