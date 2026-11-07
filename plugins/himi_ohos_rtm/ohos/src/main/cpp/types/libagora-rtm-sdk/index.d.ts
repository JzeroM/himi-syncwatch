/*
 * Copyright (c) 2024 Agora.io. All rights reserved.
 * Licensed under the MIT license.
 */
/**
 * RTM NAPI Function Definitions
 * These functions are exported from the native RTM SDK library
 */
/**
 * Get RTM SDK version
 * @returns Version string (e.g., "2.2.0")
 */
export const getVersion: () => string;
/**
 * Get error reason description for an error code
 * @param errorCode The RTM error code
 * @returns Error reason description string
 */
export const getErrorReason: (errorCode: number) => string;
/**
 * RTM client config（本地补充：ArkTS 要求对象字面量必须有明确类型，
 * `Record<string, string>` 不行——arkts-no-untyped-obj-literals）。
 */
export interface RtmClientConfig {
    appId: string;
    userId: string;
    /** 区域码，默认 GLOBAL（见 SDK `RtmAreaCode`）。 */
    areaCode?: number;
    /** 协议类型，默认 TCP_UDP（0）。 */
    protocolType?: number;
    presenceTimeout?: number;
    heartbeatInterval?: number;
    reconnectTimeout?: number;
}
/**
 * Create RTM client instance
 * @param config RTM configuration object containing appId, userId, etc.
 * @returns instanceId number
 * @throws {RtmError} If creation fails
 */
export const createRtmClient: (config: RtmClientConfig) => number;
/**
 * Release RTM client instance
 * @param instanceId The RTM client instance ID
 * @returns Error code: 0 for success, negative for failure
 */
export const releaseRtmClient: (instanceId: number) => number;
/**
 * Set RTM parameters
 * @param instanceId The RTM client instance ID
 * @param parameters JSON string containing parameters
 * @throws {RtmError} If setting parameters fails
 */
export const setParameters: (instanceId: number, parameters: string) => void;
/**
 * Base response interface
 * All RTM operation responses extend from this interface
 */
export interface BaseResponse {
    timestamp: number;
}
/**
 * Message event（本地补充：对应 SDK `MessageEvent` 的已用字段）
 */
export interface MessageEvent {
    publisher: string;
    message: string | Uint8Array;
    channelName: string;
    channelType?: number;
    messageType?: number;
    customType?: string;
}
/**
 * Presence event（本地补充：对应 SDK `PresenceEvent` 的已用字段）
 */
export interface PresenceEvent {
    eventType: number;
    publisher: string;
    channelName: string;
    channelType?: number;
}
/**
 * Link state event（本地补充：对应 SDK `LinkStateEvent` 的已用字段）
 */
export interface LinkStateEvent {
    currentState: number;
    previousState: number;
    reason: string;
    reasonCode?: number;
    operation?: number;
    serviceType?: number;
}
/**
 * Login Response
 */
export interface LoginResponse extends BaseResponse {
}
/**
 * Logout Response
 */
export interface LogoutResponse extends BaseResponse {
}
/**
 * Login to RTM service
 * @param instanceId The RTM client instance ID
 * @param token Authentication token (optional, can be empty string)
 * @returns Promise that resolves with LoginResponse
 */
export const login: (instanceId: number, token?: string) => Promise<LoginResponse>;
/**
 * Logout from RTM service
 * @param instanceId The RTM client instance ID
 * @returns Promise that resolves with LogoutResponse
 */
export const logout: (instanceId: number) => Promise<LogoutResponse>;
/**
 * Subscribe options for subscribing to a channel
 */
export interface SubscribeOptions {
    withMessage?: boolean;
    withMetadata?: boolean;
    withPresence?: boolean;
    withLock?: boolean;
    beQuiet?: boolean;
}
/**
 * Subscribe Response
 */
export interface SubscribeResponse extends BaseResponse {
    channelName: string;
}
/**
 * Subscribe to a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel to subscribe to
 * @param options Subscribe options
 * @returns Promise that resolves with SubscribeResponse
 */
export const subscribe: (instanceId: number, channelName: string, options: SubscribeOptions) => Promise<SubscribeResponse>;
/**
 * Unsubscribe Response
 */
export interface UnsubscribeResponse extends BaseResponse {
    channelName: string;
}
/**
 * Unsubscribe from a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel to unsubscribe from
 * @returns Promise that resolves with UnsubscribeResponse
 */
export const unsubscribe: (instanceId: number, channelName: string) => Promise<UnsubscribeResponse>;
/**
 * Publish options for publishing messages
 */
export interface PublishOptions {
    channelType?: number;
    customType?: string;
    storeInHistory?: boolean;
}
/**
 * Publish Response
 */
export interface PublishResponse extends BaseResponse {
}
/**
 * Publish a message to a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel to publish to
 * @param message The message content (string or Uint8Array)
 * @param options Publish options
 * @returns Promise that resolves with PublishResponse
 */
export const publish: (instanceId: number, channelName: string, message: string | Uint8Array, options: PublishOptions) => Promise<PublishResponse>;
/**
 * Renew Token Response
 */
export interface RenewTokenResponse extends BaseResponse {
}
/**
 * Renew the RTM token
 * @param instanceId The RTM client instance ID
 * @param token The new token
 * @returns Promise that resolves with RenewTokenResponse
 * @throws {RtmError} If renew token fails
 */
export const renewToken: (instanceId: number, token: string) => Promise<RenewTokenResponse>;
/**
 * Add event listener for RTM events
 * @param instanceId The RTM client instance ID
 * @param eventName The name of the event (e.g., 'linkState', 'message', etc.)
 * @param callback The callback function to be called when the event occurs
 *
 * 注意：这里**不用** `export const addEventListener: (...) => void`，
 * 而是用下面 `declare function` 的重载形式（`const` 无法重复声明）。
 */
/**
 * Add typed event listeners for RTM events.
 *
 * 用 `declare function` 重载（`const` 不能重复声明）。原 SDK 只给
 * `(event: object) => void`，这里补三个具体事件名的重载，让 ArkTS 侧
 * 回调参数直接拿到具体类型，避免 `raw as MessageEvent` 这类结构性断言
 * ——ArkTS 严格模式禁 `arkts-no-structural-typing`。
 */
export function addEventListener(instanceId: number, eventName: 'message', callback: (event: MessageEvent) => void): void;
export function addEventListener(instanceId: number, eventName: 'presence', callback: (event: PresenceEvent) => void): void;
export function addEventListener(instanceId: number, eventName: 'linkState', callback: (event: LinkStateEvent) => void): void;
export function addEventListener(instanceId: number, eventName: string, callback: (event: object) => void): void;
/**
 * Remove event listener for RTM events
 * @param instanceId The RTM client instance ID
 * @param eventName The name of the event to remove the listener for
 * @param callback Optional callback function to remove. If not provided, removes all listeners for the event.
 */
export const removeEventListener: (instanceId: number, eventName: string, callback?: (event: object) => void) => void;
/**
 * Channel information
 */
export interface ChannelInfo {
    channelName: string;
    channelType: number;
}
/**
 * State item
 */
export interface StateItem {
    key: string;
    value: string;
}
/**
 * User state
 */
export interface UserState {
    userId: string;
    states: StateItem[];
}
/**
 * Presence options
 */
export interface PresenceOptions {
    includeUserId?: boolean;
    includeState?: boolean;
    page?: string;
}
/**
 * Who now response
 */
export interface WhoNowResponse extends BaseResponse {
    userStateList: UserState[];
    totalOccupancy: number;
    nextPage: string;
}
/**
 * Query who is currently in a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel to query
 * @param channelType The type of the channel
 * @param options The query options
 * @returns Promise that resolves with WhoNowResponse
 * @throws {RtmError} If whoNow fails
 */
export const whoNow: (instanceId: number, channelName: string, channelType: number, options: PresenceOptions) => Promise<WhoNowResponse>;
/**
 * Where now response
 */
export interface WhereNowResponse extends BaseResponse {
    channels: ChannelInfo[];
}
/**
 * Query which channels a user has joined
 * @param instanceId The RTM client instance ID
 * @param userId The ID of the user to query
 * @returns Promise that resolves with WhereNowResponse
 * @throws {RtmError} If whereNow fails
 */
export const whereNow: (instanceId: number, userId: string) => Promise<WhereNowResponse>;
/**
 * Set state response
 */
export interface SetStateResponse extends BaseResponse {
}
/**
 * Remove state response
 */
export interface RemoveStateResponse extends BaseResponse {
}
/**
 * Set user state in a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param items Array of state items to set
 * @returns Promise that resolves with SetStateResponse
 * @throws {RtmError} If setState fails
 */
export const setState: (instanceId: number, channelName: string, channelType: number, items: StateItem[]) => Promise<SetStateResponse>;
/**
 * Remove user state from a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param keys Array of state keys to remove. Empty array removes all states.
 * @returns Promise that resolves with RemoveStateResponse
 * @throws {RtmError} If removeState fails
 */
export const removeState: (instanceId: number, channelName: string, channelType: number, keys: string[]) => Promise<RemoveStateResponse>;
/**
 * Get state response
 */
export interface GetStateResponse extends BaseResponse {
    userState: UserState;
}
/**
 * Get user state from a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param userId The ID of the user whose state to retrieve
 * @returns Promise that resolves with GetStateResponse
 * @throws {RtmError} If getState fails
 */
export const getState: (instanceId: number, channelName: string, channelType: number, userId: string) => Promise<GetStateResponse>;
/**
 * Metadata item
 */
export interface MetadataItem {
    key: string;
    value: string;
    revision?: number;
    authorUserId?: string;
    updateTs?: number;
}
/**
 * Metadata structure
 */
export interface Metadata {
    majorRevision: number;
    items: MetadataItem[];
}
/**
 * Metadata options for storage operations
 */
export interface MetadataOptions {
    lockName?: string;
    recordTs?: boolean;
    recordUserId?: boolean;
}
/**
 * Set channel metadata response
 */
export interface SetChannelMetadataResponse extends BaseResponse {
    channelName: string;
    channelType: number;
}
/**
 * Set metadata for a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param data The metadata to set (includes majorRevision and items)
 * @param options Optional settings for this operation
 * @returns Promise that resolves with SetChannelMetadataResponse
 * @throws {RtmError} If setChannelMetadata fails
 */
export const setChannelMetadata: (instanceId: number, channelName: string, channelType: number, data: Metadata, options: MetadataOptions) => Promise<SetChannelMetadataResponse>;
/**
 * Update channel metadata response
 */
export interface UpdateChannelMetadataResponse extends BaseResponse {
    channelName: string;
    channelType: number;
}
/**
 * Update metadata for a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param data The metadata to update (includes majorRevision and items)
 * @param options Optional settings for this operation
 * @returns Promise that resolves with UpdateChannelMetadataResponse
 * @throws {RtmError} If updateChannelMetadata fails
 */
export const updateChannelMetadata: (instanceId: number, channelName: string, channelType: number, data: Metadata, options: MetadataOptions) => Promise<UpdateChannelMetadataResponse>;
/**
 * Remove channel metadata response
 */
export interface RemoveChannelMetadataResponse extends BaseResponse {
    channelName: string;
    channelType: number;
}
export interface GetChannelMetadataResponse extends BaseResponse {
    channelName: string;
    channelType: number;
    data: Metadata;
}
export interface SetUserMetadataResponse extends BaseResponse {
    userId: string;
}
export interface UpdateUserMetadataResponse extends BaseResponse {
    userId: string;
}
export interface RemoveUserMetadataResponse extends BaseResponse {
    userId: string;
}
export interface SubscribeUserMetadataResponse extends BaseResponse {
    userId: string;
}
export interface UnsubscribeUserMetadataResponse extends BaseResponse {
    userId: string;
}
export interface GetUserMetadataResponse extends BaseResponse {
    userId: string;
    data: Metadata;
}
/**
 * Remove metadata from a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param data The metadata to remove (includes majorRevision and items). If items is empty, removes all metadata
 * @param options Optional settings for this operation
 * @returns Promise that resolves with RemoveChannelMetadataResponse
 * @throws {RtmError} If removeChannelMetadata fails
 */
export const removeChannelMetadata: (instanceId: number, channelName: string, channelType: number, data: Metadata, options: MetadataOptions) => Promise<RemoveChannelMetadataResponse>;
export const getChannelMetadata: (instanceId: number, channelName: string, channelType: number) => Promise<GetChannelMetadataResponse>;
export const setUserMetadata: (instanceId: number, userId: string, data: Metadata, options?: MetadataOptions) => Promise<SetUserMetadataResponse>;
export const updateUserMetadata: (instanceId: number, userId: string, data: Metadata, options?: MetadataOptions) => Promise<UpdateUserMetadataResponse>;
export const removeUserMetadata: (instanceId: number, userId: string, data: Metadata, options?: MetadataOptions) => Promise<RemoveUserMetadataResponse>;
export const subscribeUserMetadata: (instanceId: number, userId: string) => Promise<SubscribeUserMetadataResponse>;
export const unsubscribeUserMetadata: (instanceId: number, userId: string) => Promise<UnsubscribeUserMetadataResponse>;
export const getUserMetadata: (instanceId: number, userId: string) => Promise<GetUserMetadataResponse>;
/**
 * Lock detail information
 */
export interface LockDetail {
    lockName: string;
    owner: string;
    ttl: number;
}
/**
 * Options for setLock operation
 */
export interface SetLockOptions {
    ttl?: number;
}
/**
 * Options for acquireLock operation
 */
export interface AcquireLockOptions {
    retry?: boolean;
}
/**
 * Lock operation response
 */
export interface LockOperationResponse extends BaseResponse {
    channelName: string;
    channelType: number;
    lockName: string;
}
/**
 * Set lock response
 */
export interface SetLockResponse extends LockOperationResponse {
}
/**
 * Remove lock response
 */
export interface RemoveLockResponse extends LockOperationResponse {
}
/**
 * Acquire lock response
 */
export interface AcquireLockResponse extends LockOperationResponse {
}
/**
 * Release lock response
 */
export interface ReleaseLockResponse extends LockOperationResponse {
}
/**
 * Revoke lock response
 */
export interface RevokeLockResponse extends LockOperationResponse {
}
/**
 * Get locks response
 */
export interface GetLocksResponse extends BaseResponse {
    channelName: string;
    channelType: number;
    lockDetails: LockDetail[];
}
/**
 * Set a lock in a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param lockName The name of the lock
 * @param options Optional settings (ttl)
 * @returns Promise that resolves with SetLockResponse
 * @throws {RtmError} If setLock fails
 */
export const setLock: (instanceId: number, channelName: string, channelType: number, lockName: string, options?: SetLockOptions) => Promise<SetLockResponse>;
/**
 * Get all locks in a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @returns Promise that resolves with GetLocksResponse
 * @throws {RtmError} If getLocks fails
 */
export const getLocks: (instanceId: number, channelName: string, channelType: number) => Promise<GetLocksResponse>;
/**
 * Remove a lock from a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param lockName The name of the lock to remove
 * @returns Promise that resolves with RemoveLockResponse
 * @throws {RtmError} If removeLock fails
 */
export const removeLock: (instanceId: number, channelName: string, channelType: number, lockName: string) => Promise<RemoveLockResponse>;
/**
 * Acquire a lock
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param lockName The name of the lock to acquire
 * @param options Optional settings (retry)
 * @returns Promise that resolves with AcquireLockResponse
 * @throws {RtmError} If acquireLock fails
 */
export const acquireLock: (instanceId: number, channelName: string, channelType: number, lockName: string, options?: AcquireLockOptions) => Promise<AcquireLockResponse>;
/**
 * Release a lock
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param lockName The name of the lock to release
 * @returns Promise that resolves with ReleaseLockResponse
 * @throws {RtmError} If releaseLock fails
 */
export const releaseLock: (instanceId: number, channelName: string, channelType: number, lockName: string) => Promise<ReleaseLockResponse>;
/**
 * Revoke a lock from a user
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the channel
 * @param channelType The type of the channel
 * @param lockName The name of the lock to revoke
 * @param owner The user ID of the lock owner
 * @returns Promise that resolves with RevokeLockResponse
 * @throws {RtmError} If revokeLock fails
 */
export const revokeLock: (instanceId: number, channelName: string, channelType: number, lockName: string, owner: string) => Promise<RevokeLockResponse>;
// ============================================================================
// History (Message History) Types
// ============================================================================
/**
 * Options for retrieving history messages
 */
export interface GetHistoryMessagesOptions {
    /**
     * Max number of messages to retrieve (1-100, default: 100)
     */
    messageCount?: number;
    /**
     * Start timestamp in milliseconds (default: 0)
     */
    start?: number;
    /**
     * End timestamp in milliseconds (default: 0)
     */
    end?: number;
}
/**
 * Historical message structure
 */
export interface HistoryMessage {
    /**
     * Message content (string or Uint8Array)
     */
    message: string | Uint8Array;
    /**
     * Message type (STRING or BINARY)
     */
    messageType: number;
    /**
     * User ID of message publisher
     */
    publisher: string;
    /**
     * Custom type identifier
     */
    customType: string;
    /**
     * Server timestamp in milliseconds
     */
    timestamp: number;
}
/**
 * Response from getMessages operation
 */
export interface GetMessagesResponse extends BaseResponse {
    /**
     * Starting timestamp for next batch (0 if no more messages)
     */
    newStart: number;
    /**
     * Array of historical messages
     */
    messageList: HistoryMessage[];
}
/**
 * Retrieve historical messages from a channel
 * @param instanceId The RTM client instance ID
 * @param channelName The channel name to query history from
 * @param channelType The channel type (MESSAGE or USER, NOT STREAM)
 * @param options Optional query parameters
 * @returns Promise that resolves with GetMessagesResponse
 * @throws {RtmError} If getMessages fails
 */
export const getMessages: (instanceId: number, channelName: string, channelType: number, options?: GetHistoryMessagesOptions) => Promise<GetMessagesResponse>;
// ============================================================================
// StreamChannel Functions
// ============================================================================
/**
 * Create a stream channel instance
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @throws {RtmError} If creation fails
 */
export const createStreamChannel: (instanceId: number, channelName: string) => void;
/**
 * Release a stream channel instance
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel to release
 * @returns Error code (0 for success)
 */
export const releaseStreamChannel: (instanceId: number, channelName: string) => number;
/**
 * Join options for stream channel
 */
export interface JoinOptions {
    token?: string;
    withMetadata?: boolean;
    withPresence?: boolean;
    withLock?: boolean;
    beQuiet?: boolean;
}
/**
 * Response for stream channel join
 */
export interface JoinResponse extends BaseResponse {
    channelName: string;
}
/**
 * Response for stream channel leave
 */
export interface LeaveResponse extends BaseResponse {
    channelName: string;
}
/**
 * Join a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param options Join options
 * @returns Promise resolving with join response
 * @throws {RtmError} If join fails
 */
export const join: (instanceId: number, channelName: string, options?: JoinOptions) => Promise<JoinResponse>;
/**
 * Leave a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @returns Promise resolving with leave response
 * @throws {RtmError} If leave fails
 */
export const leave: (instanceId: number, channelName: string) => Promise<LeaveResponse>;
/**
 * Renew token for a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param token The new token
 * @returns Promise resolving with RenewTokenResponse
 * @throws {RtmError} If renew token fails
 */
export const renewStreamChannelToken: (instanceId: number, channelName: string, token: string) => Promise<RenewTokenResponse>;
/**
 * Set parameters for a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param parameters JSON string containing the parameters
 * @throws {RtmError} If setting parameters fails
 */
export const setStreamChannelParameters: (instanceId: number, channelName: string, parameters: string) => void;
/**
 * Options for joining a topic
 */
export interface JoinTopicOptions {
    qos?: number;
    priority?: number;
    meta?: string;
    syncWithMedia?: boolean;
}
/**
 * Options for publishing topic message
 */
export interface TopicMessageOptions {
    sendTs?: number;
    customType?: string;
}
/**
 * Response for join topic operation
 */
export interface JoinTopicResponse extends BaseResponse {
    topicName: string;
}
/**
 * Response for leave topic operation
 */
export interface LeaveTopicResponse extends BaseResponse {
    topicName: string;
}
/**
 * Response for publish topic message operation
 */
export interface PublishTopicMessageResponse extends BaseResponse {
    topicName: string;
}
/**
 * Join a topic in a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param topicName The name of the topic
 * @param options Join topic options
 * @returns Promise resolving with join topic response
 * @throws {RtmError} If join topic fails
 */
export const joinTopic: (instanceId: number, channelName: string, topicName: string, options?: JoinTopicOptions) => Promise<JoinTopicResponse>;
/**
 * Leave a topic in a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param topicName The name of the topic
 * @returns Promise resolving with leave topic response
 * @throws {RtmError} If leave topic fails
 */
export const leaveTopic: (instanceId: number, channelName: string, topicName: string) => Promise<LeaveTopicResponse>;
/**
 * Publish a message to a topic in a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param topicName The name of the topic
 * @param message The message content (string or Uint8Array)
 * @param options Topic message options
 * @returns Promise resolving with publish response
 * @throws {RtmError} If publish fails
 */
export const publishTopicMessage: (instanceId: number, channelName: string, topicName: string, message: string | Uint8Array, options?: TopicMessageOptions) => Promise<PublishTopicMessageResponse>;
/**
 * Options for subscribing/unsubscribing to a topic
 */
export interface TopicOptions {
    users?: string[];
}
/**
 * Response for subscribe topic operation
 */
export interface SubscribeTopicResponse extends BaseResponse {
    topicName: string;
    succeedUsers: string[];
    failedUsers: string[];
}
/**
 * Response for unsubscribe topic operation
 */
export interface UnsubscribeTopicResponse extends BaseResponse {
    topicName: string;
}
/**
 * Subscribe to a topic in a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param topicName The name of the topic
 * @param options Subscribe options
 * @returns Promise resolving with subscribe response
 * @throws {RtmError} If subscribe fails
 */
export const subscribeTopic: (instanceId: number, channelName: string, topicName: string, options?: TopicOptions) => Promise<SubscribeTopicResponse>;
/**
 * Unsubscribe from a topic in a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param topicName The name of the topic
 * @param options Unsubscribe options
 * @returns Promise resolving with unsubscribe response
 * @throws {RtmError} If unsubscribe fails
 */
export const unsubscribeTopic: (instanceId: number, channelName: string, topicName: string, options?: TopicOptions) => Promise<UnsubscribeTopicResponse>;
/**
 * Response for get subscribed user list operation
 */
export interface GetSubscribedUserListResponse extends BaseResponse {
    topicName: string;
    users: string[];
}
/**
 * Get the list of users subscribed to a topic in a stream channel
 * @param instanceId The RTM client instance ID
 * @param channelName The name of the stream channel
 * @param topicName The name of the topic
 * @returns Promise resolving with get subscribed user list response
 * @throws {RtmError} If get subscribed user list fails
 */
export const getSubscribedUserList: (instanceId: number, channelName: string, topicName: string) => Promise<GetSubscribedUserListResponse>;
/**
 * Release the native handle (bridge cleanup)
 */
export const releaseNativeHandle: () => void;
/**
 * Get system event handler NAPI object for network monitoring
 * This function returns an object with methods to handle system events from TypeScript layer
 * @returns Object with handleNetworkChange and getNativeHandle methods
 */
export const getSystemEventHandlerNapiObject: () => Record<string, (ref: bigint, obj?: object) => object>;
