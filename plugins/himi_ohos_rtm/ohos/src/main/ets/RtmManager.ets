/**
 * 声网 RTM ArkTS SDK 封装（鸿蒙）。
 *
 * 与 Windows `RtmClient`（C++）职责一致：把 SDK 的 Promise API 包成
 * 便于 MethodChannel 调用的形态，并把事件回调转成统一 JSON 结构。
 */
import { RtmClient, RtmChannelType } from '@shengwang/rtm-full';
import type {
  RtmConfig,
  MessageEvent,
  PresenceEvent,
  SubscribeOptions,
  PublishOptions,
  PresenceOptions,
  Metadata,
  MetadataItem,
  UserState,
  WhoNowResponse,
  GetChannelMetadataResponse,
} from '@shengwang/rtm-full';
import hilog from '@ohos.hilog';

const DOMAIN: number = 0x0001;
const TAG: string = 'HimiOhosRtm';

/** 事件回调（由 Plugin 转 EventChannel）。 */
export type RtmEventSink = (event: Map<string, Object>) => void;

export class RtmManager {
  private client: RtmClient | null = null;
  private userId: string = '';
  private sink: RtmEventSink | null = null;

  setEventSink(sink: RtmEventSink | null): void {
    this.sink = sink;
  }

  isReady(): boolean {
    return this.client !== null;
  }

  /** 创建客户端并挂事件监听（不登录）。 */
  initialize(appId: string, userId: string): void {
    if (this.client !== null) {
      this.release();
    }
    this.userId = userId;
    const config: RtmConfig = { appId: appId, userId: userId };
    this.client = new RtmClient(config);
    this.attachListeners(this.client);
    hilog.info(DOMAIN, TAG, '初始化成功 userId=%{public}s', userId);
  }

  private attachListeners(client: RtmClient): void {
    // 消息：{publisher, message}
    client.addEventListener('message', (raw: object): void => {
      const e = raw as MessageEvent;
      const out: Map<string, Object> = new Map<string, Object>();
      out.set('event', 'message');
      out.set('publisher', e.publisher ?? '');
      out.set('message', typeof e.message === 'string' ? e.message : '');
      this.emit(out);
    });
    // Presence：{type, publisher}
    client.addEventListener('presence', (raw: object): void => {
      const e = raw as PresenceEvent;
      const out: Map<string, Object> = new Map<string, Object>();
      out.set('event', 'presence');
      out.set('type', this.mapPresenceType(e.eventType));
      out.set('publisher', e.publisher ?? '');
      this.emit(out);
    });
    // 连接状态（诊断用）
    client.addEventListener('linkState', (raw: object): void => {
      const out: Map<string, Object> = new Map<string, Object>();
      out.set('event', 'connection');
      out.set('state', `${raw}`);
      this.emit(out);
    });
  }

  private emit(event: Map<string, Object>): void {
    if (this.sink !== null) {
      this.sink(event);
    }
  }

  /**
   * Presence 事件类型 → 字符串（与 Dart `RtmPresenceEventType` 对齐）。
   *
   * SDK 枚举（RtmBase.d.ets）：NONE=0 / SNAPSHOT=1 / INTERVAL=2 /
   * REMOTE_JOIN_CHANNEL=3 / REMOTE_LEAVE_CHANNEL=4 / REMOTE_TIMEOUT=5。
   */
  private mapPresenceType(t: number): string {
    if (t === 3) {
      return 'join';
    }
    if (t === 4) {
      return 'leave';
    }
    if (t === 5) {
      return 'timeout';
    }
    return 'other';
  }

  async login(token: string): Promise<void> {
    const c = this.requireClient();
    await c.login(token);
    hilog.info(DOMAIN, TAG, '登录成功');
  }

  async logout(): Promise<void> {
    const c = this.requireClient();
    await c.logout();
  }

  async subscribe(channel: string): Promise<void> {
    const c = this.requireClient();
    const options: SubscribeOptions = {
      withMessage: true,
      withMetadata: false,
      withPresence: true,
      withLock: false,
    };
    await c.subscribe(channel, options);
  }

  async unsubscribe(channel: string): Promise<void> {
    const c = this.requireClient();
    await c.unsubscribe(channel);
  }

  async publish(channel: string, message: string): Promise<void> {
    const c = this.requireClient();
    const options: PublishOptions = {
      channelType: RtmChannelType.MESSAGE,
      customType: '',
    };
    await c.publish(channel, message, options);
  }

  /** 在线人数 + 用户 ID 列表（一次 whoNow）。 */
  async getOnlineUsers(channel: string): Promise<Map<string, Object>> {
    const c = this.requireClient();
    const options: PresenceOptions = {
      includeUserId: true,
      includeState: false,
    };
    const resp: WhoNowResponse =
      await c.presence.whoNow(channel, RtmChannelType.MESSAGE, options);
    const ids: string[] = [];
    const list: UserState[] = resp.userStateList;
    if (list !== undefined) {
      for (const u of list) {
        const uid: string = u.userId;
        if (uid !== undefined && uid.length > 0) {
          ids.push(uid);
        }
      }
    }
    const out: Map<string, Object> = new Map<string, Object>();
    out.set('count', resp.totalOccupancy ?? ids.length);
    out.set('userIds', ids);
    return out;
  }

  /** 写频道元数据；返回新 revision（失败由调用方兜底）。 */
  async setChannelMetadata(
    channel: string,
    metadata: Map<string, string>,
  ): Promise<string> {
    const c = this.requireClient();
    const items: MetadataItem[] = [];
    const keys: string[] = Array.from(metadata.keys());
    for (const k of keys) {
      const v: string = metadata.get(k) ?? '';
      const item: MetadataItem = { key: k, value: v };
      items.push(item);
    }
    const md: Metadata = { majorRevision: -1, items: items };
    // 注意：SetChannelMetadataResponse **没有** metadata 字段（只有
    // channelName/channelType），故无法回读 revision；返回空串，
    // 由 Dart 侧 `storage_null` 之外的语义兜底。
    await c.storage.setChannelMetadata(channel, RtmChannelType.MESSAGE, md);
    return '';
  }

  /** 读频道元数据 → {metadata, updatedAt}。 */
  async getChannelMetadata(channel: string): Promise<Map<string, Object>> {
    const c = this.requireClient();
    const resp: GetChannelMetadataResponse = await c.storage.getChannelMetadata(
      channel, RtmChannelType.MESSAGE);
    const map: Map<string, string> = new Map<string, string>();
    // 注意：GetChannelMetadataResponse 的字段名是 **data**（不是 metadata）。
    const data: Metadata = resp.data;
    const items: MetadataItem[] = data.items;
    if (items !== undefined) {
      for (const it of items) {
        const k: string = it.key;
        if (k !== undefined) {
          map.set(k, it.value ?? '');
        }
      }
    }
    const out: Map<string, Object> = new Map<string, Object>();
    out.set('metadata', map);
    out.set('updatedAt', `${data !== undefined ? data.majorRevision : ''}`);
    return out;
  }

  release(): void {
    if (this.client !== null) {
      try {
        this.client.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'release 异常: %{public}s', String(e));
      }
      this.client = null;
    }
    this.sink = null;
  }

  private requireClient(): RtmClient {
    const c: RtmClient | null = this.client;
    if (c === null) {
      throw new Error('RTM client not initialized');
    }
    return c;
  }
}
