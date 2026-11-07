/**
 * 声网 RTM NAPI 直连封装（鸿蒙）。
 *
 * 为什么不用 `@shengwang/rtm-full` HAR：
 * 它是 **bytecode HAR**（`metadata.byteCodeHar: true`），hvigor 强制要求
 * `buildOption.strictMode.useNormalizedOHMUrl: true` 才能解析；而该开关是
 * **项目级**的，会改变所有模块的 OHM URL 解析规则，导致 Flutter-OH 生成的
 * `entry` 模块（`entryPath` 是目录 `src/main/`）找不到 `EntryAbility` →
 * 启动即闪退：
 *   Cannot find module 'ets/entryability/EntryAbility',
 *   which is application Entry Point
 *
 * 绕开办法：bytecode HAR 内部的 `ets/modules.abc` 只是一层薄壳，唯一关键
 * 字符串是 `@normalized:Y&&&libagora-rtm-sdk.so&`——真正的实现全在
 * `libagora-rtm-sdk.so` 这个 **标准 NAPI 模块**里：
 *   - `nm_modname = "agora-rtm-sdk"`（文件名去掉 lib/.so，规则同 mpv）
 *   - `nm_register_func` → `napi_define_properties` 导出 49 个函数
 *   - `.rodata` 里能找到全部 49 个导出名
 *
 * 所以这里直接 `import ... from 'libagora-rtm-sdk.so'`，与 `mpv.har` 用
 * `import libmpv from 'libmpv_wrapper.so'` 的做法完全一致。仍然是声网
 * 官方 SDK 与官方服务器，跨端互通不变，只是不需要 `useNormalizedOHMUrl`。
 */
import {
  createRtmClient,
  releaseRtmClient,
  login,
  logout,
  subscribe,
  unsubscribe,
  publish,
  addEventListener,
  whoNow,
  setChannelMetadata,
  getChannelMetadata,
  getVersion,
} from 'libagora-rtm-sdk.so';
// 直接复用 SDK 的类型声明，避免自定义 interface 与 SDK interface 之间
// 出现 `as` 断言（ArkTS 禁 arkts-no-structural-typing）。
import type {
  RtmClientConfig,
  Metadata,
  MetadataItem,
  MetadataOptions,
  SubscribeOptions,
  PublishOptions,
  PresenceOptions,
  MessageEvent,
  PresenceEvent,
  LinkStateEvent,
} from 'libagora-rtm-sdk.so';
import hilog from '@ohos.hilog';
import util from '@ohos.util';

const DOMAIN: number = 0x0001;
const TAG: string = 'HimiOhosRtm';

/** `RtmChannelType.MESSAGE`（见 SDK `RtmBase.d.ets`）。 */
const CHANNEL_TYPE_MESSAGE: number = 1;

/** 事件回调（由 Plugin 转 EventChannel）。 */
export type RtmEventSink = (event: Map<string, Object>) => void;

export class RtmManager {
  /** NAPI 实例句柄；-1 表示未创建。 */
  private instanceId: number = -1;
  private userId: string = '';
  private sink: RtmEventSink | null = null;

  setEventSink(sink: RtmEventSink | null): void {
    this.sink = sink;
  }

  isReady(): boolean {
    return this.instanceId >= 0;
  }

  /** 创建客户端并挂事件监听（不登录）。 */
  initialize(appId: string, userId: string): void {
    if (this.instanceId >= 0) {
      this.release();
    }
    this.userId = userId;
    // 必须用 index.d.ts 声明的 RtmClientConfig（ArkTS 禁无类型对象字面量）。
    const config: RtmClientConfig = { appId: appId, userId: userId };
    const id: number = createRtmClient(config);
    if (id < 0) {
      throw new Error(`createRtmClient 失败, code=${id}`);
    }
    this.instanceId = id;
    this.attachListeners(id);
    hilog.info(DOMAIN, TAG, '初始化成功 userId=%{public}s sdk=%{public}s',
      userId, getVersion());
  }

  private attachListeners(id: number): void {
    // 消息：{publisher, message}
    // 用 index.d.ts 的 'message' 重载，回调参数已是 MessageEvent，
    // 无需 `as`（ArkTS 禁结构性断言）。
    addEventListener(id, 'message', (e: MessageEvent): void => {
      const out: Map<string, Object> = new Map<string, Object>();
      out.set('event', 'message');
      out.set('publisher', e.publisher ?? '');
      // 【632 根因】旧实现 `typeof e.message === 'string' ? e.message : ''`
      // 在 SDK 返回 Uint8Array（BINARY 类型，或跨 NAPI 语言边界的包装）时
      // 会把内容丢成空串 → Dart 侧 jsonDecode('') 抛异常被 catch 静默吞掉
      // → **所有** RTM 消息（roomInfo / join / heartbeat / syncPlay / pause）
      // 全部失效，表现为：中途进房资源列表为空、误报房间已解散、
      // 房主暂停观众不暂停。
      // Windows 侧是 `assign(message, messageLength)` 按字节取，故不受影响。
      out.set('message', this.extractMessageText(e.message));
      this.emit(out);
    });
    // Presence：{type, publisher}
    addEventListener(id, 'presence', (e: PresenceEvent): void => {
      const out: Map<string, Object> = new Map<string, Object>();
      out.set('event', 'presence');
      out.set('type', this.mapPresenceType(e.eventType));
      out.set('publisher', e.publisher ?? '');
      this.emit(out);
    });
    // 连接状态（诊断用）
    addEventListener(id, 'linkState', (e: LinkStateEvent): void => {
      const out: Map<string, Object> = new Map<string, Object>();
      out.set('event', 'connection');
      out.set('state', `${e.currentState}`);
      if (e.reason !== undefined && e.reason.length > 0) {
        out.set('reason', e.reason);
      }
      this.emit(out);
    });
  }

  private emit(event: Map<string, Object>): void {
    if (this.sink !== null) {
      this.sink(event);
    }
  }

  /**
   * 把 SDK 的消息内容统一转成 UTF-8 字符串。
   *
   * 632 根因修复：`MessageEvent.message` 的声明是 `string | Uint8Array`
   * （见 SDK `RtmEvent.d.ets`）：
   * - `RtmMessageType.STRING` → string
   * - `RtmMessageType.BINARY` → Uint8Array
   *
   * 旧实现只认 `string`，其余一律丢成空串，导致 Dart 侧 `jsonDecode('')`
   * 抛异常并被 catch 静默吞掉 → 整条消息失效。这里用 TextDecoder 兜底，
   * 保证两种形态都能还原成原始 JSON 文本。
   */
  private extractMessageText(raw: string | Uint8Array | undefined): string {
    if (raw === undefined || raw === null) {
      return '';
    }
    if (typeof raw === 'string') {
      return raw;
    }
    // 632：走到这里 raw 已被 TS 收窄为 Uint8Array，无需 `as` 断言
    // （ArkTS 严格模式禁 arkts-no-structural-typing）。
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(raw);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '消息解码失败: %{public}s', String(err));
      return '';
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
    const id = this.requireId();
    await login(id, token);
    hilog.info(DOMAIN, TAG, '登录成功');
  }

  async logout(): Promise<void> {
    const id = this.requireId();
    await logout(id);
  }

  async subscribe(channel: string): Promise<void> {
    const id = this.requireId();
    const options: SubscribeOptions = {
      withMessage: true,
      withMetadata: false,
      withPresence: true,
      withLock: false,
    };
    await subscribe(id, channel, options);
  }

  async unsubscribe(channel: string): Promise<void> {
    const id = this.requireId();
    await unsubscribe(id, channel);
  }

  async publish(channel: string, message: string): Promise<void> {
    const id = this.requireId();
    const options: PublishOptions = {
      channelType: CHANNEL_TYPE_MESSAGE,
      customType: '',
    };
    await publish(id, channel, message, options);
  }

  /** 在线人数 + 用户 ID 列表（一次 whoNow）。 */
  async getOnlineUsers(channel: string): Promise<Map<string, Object>> {
    const id = this.requireId();
    const options: PresenceOptions = {
      includeUserId: true,
      includeState: false,
    };
    // 注意：whoNow 的返回类型由 index.d.ts 推断为 WhoNowResponse，
    // 不能写 `as RtmWhoNowResponse`——ArkTS 禁结构性类型断言
    // （arkts-no-structural-typing）。
    const resp = await whoNow(id, channel, CHANNEL_TYPE_MESSAGE, options);
    const ids: string[] = [];
    const list = resp.userStateList;
    if (list !== undefined && list !== null) {
      for (const u of list) {
        const uid: string = u.userId;
        if (uid !== undefined && uid.length > 0) {
          ids.push(uid);
        }
      }
    }
    const out: Map<string, Object> = new Map<string, Object>();
    const total: number = resp.totalOccupancy;
    out.set('count', total !== undefined && total > 0 ? total : ids.length);
    out.set('userIds', ids);
    return out;
  }

  /** 写频道元数据；返回新 revision（失败由调用方兜底）。 */
  async setChannelMetadata(
    channel: string,
    metadata: Map<string, string>,
  ): Promise<string> {
    const id = this.requireId();
    const items: MetadataItem[] = [];
    const keys: string[] = Array.from(metadata.keys());
    for (const k of keys) {
      const v: string = metadata.get(k) ?? '';
      const item: MetadataItem = { key: k, value: v };
      items.push(item);
    }
    const md: Metadata = { majorRevision: -1, items: items };
    const opts: MetadataOptions = {};
    // 注意：SetChannelMetadataResponse **没有** metadata 字段（只有
    // channelName/channelType），故无法回读 revision；返回空串，
    // 由 Dart 侧 `storage_null` 之外的语义兜底。
    await setChannelMetadata(id, channel, CHANNEL_TYPE_MESSAGE, md, opts);
    return '';
  }

  /** 读频道元数据 → {metadata, updatedAt}。 */
  async getChannelMetadata(channel: string): Promise<Map<string, Object>> {
    const id = this.requireId();
    // 同 whoNow：不能 `as RtmGetChannelMetadataResponse`（ArkTS 禁结构性断言）。
    const resp = await getChannelMetadata(id, channel, CHANNEL_TYPE_MESSAGE);
    const map: Map<string, string> = new Map<string, string>();
    // 注意：GetChannelMetadataResponse 的字段名是 **data**（不是 metadata）。
    const data = resp.data;
    if (data !== undefined && data !== null) {
      const items = data.items;
      if (items !== undefined && items !== null) {
        for (const it of items) {
          const k: string = it.key;
          if (k !== undefined) {
            map.set(k, it.value ?? '');
          }
        }
      }
    }
    const out: Map<string, Object> = new Map<string, Object>();
    out.set('metadata', map);
    out.set('updatedAt',
      `${data !== undefined && data !== null ? data.majorRevision : ''}`);
    return out;
  }

  release(): void {
    if (this.instanceId >= 0) {
      try {
        releaseRtmClient(this.instanceId);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'release 异常: %{public}s', String(e));
      }
      this.instanceId = -1;
    }
    // 635：**不再清空 sink**。
    //
    // sink 是 Plugin 提供的「事件出口」回调，与 client 实例生命周期无关。
    // 旧实现在这里 `this.sink = null`，而重建 client 时（`initialize` 会先
    // 调 `release()`）**没有任何地方恢复它** → `emit()` 里
    // `if (this.sink !== null)` 恒为假 → 所有事件被丢弃。
    //
    // 真机表现（重进房 / 房主重开房后再加入）：
    // - 在线人数正常（whoNow 直调 MethodChannel，不经 sink）
    // - 播报正常（本地 _addBroadcastMessage，不经 sink）
    // - **资源列表为空**（roomInfo 走 emit → sink 为 null → 丢弃）
    // - **约 20 秒后被踢**（收不到 roomInfo → 超时 → 误判房间解散）
    //
    // sink 的清空只在 Plugin `onDetachedFromEngine`（引擎真正销毁）时做。
  }

  private requireId(): number {
    const id: number = this.instanceId;
    if (id < 0) {
      throw new Error('RTM client not initialized');
    }
    return id;
  }
}
