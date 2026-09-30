#include "rtm_client.h"

namespace himi_windows_rtm {

using namespace agora::rtm;

namespace {
const char* OkText = "ok";
}  // namespace

RtmClient::~RtmClient() {
  Release();
}

void RtmClient::SetEventHandler(EventHandler handler) {
  std::lock_guard<std::mutex> lock(mutex_);
  handler_ = std::move(handler);
}

void RtmClient::Emit(RtmEvent event) {
  EventHandler handler;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    handler = handler_;
  }
  if (handler) {
    handler(event);
  }
}

std::string RtmClient::ErrText(RTM_ERROR_CODE code) {
  if (code == RTM_ERROR_OK) {
    return OkText;
  }
  const char* reason = getErrorReason(static_cast<int>(code));
  return std::string("错误码 ") + (reason ? reason : "unknown");
}

uint64_t RtmClient::Track(RTM_ERROR_CODE /*unused*/, const char* method, uint64_t requestId) {
  if (requestId != 0) {
    std::lock_guard<std::mutex> lock(mutex_);
    pending_[requestId] = method;
  }
  return requestId;
}

std::string RtmClient::TakeMethod(uint64_t requestId) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = pending_.find(requestId);
  if (it == pending_.end()) {
    return "";
  }
  std::string method = it->second;
  pending_.erase(it);
  return method;
}

bool RtmClient::Initialize(const std::string& appId, const std::string& userId) {
  Release();

  app_id_ = appId;
  user_id_ = userId;

  RtmConfig config;
  config.appId = app_id_.c_str();
  config.userId = user_id_.c_str();
  config.areaCode = RTM_AREA_CODE_GLOB;
  config.useStringUserId = true;
  config.presenceTimeout = 300;
  config.heartbeatInterval = 15;
  config.eventHandler = this;

  int errorCode = 0;
  client_ = createAgoraRtmClient(config, errorCode);
  if (!client_) {
    return false;
  }
  storage_ = client_->getStorage();
  presence_ = client_->getPresence();
  return true;
}

uint64_t RtmClient::Login(const std::string& token) {
  if (!client_) {
    return 0;
  }
  uint64_t requestId = 0;
  client_->login(token.empty() ? "" : token.c_str(), requestId);
  return Track(RTM_ERROR_OK, "login", requestId);
}

void RtmClient::Logout() {
  if (!client_) {
    return;
  }
  uint64_t requestId = 0;
  client_->logout(requestId);
  Track(RTM_ERROR_OK, "logout", requestId);
}

uint64_t RtmClient::Subscribe(const std::string& channel) {
  if (!client_) {
    return 0;
  }
  SubscribeOptions options;
  options.withMessage = true;
  options.withMetadata = true;
  options.withPresence = true;
  uint64_t requestId = 0;
  client_->subscribe(channel.c_str(), options, requestId);
  return Track(RTM_ERROR_OK, "subscribe", requestId);
}

void RtmClient::Unsubscribe(const std::string& channel) {
  if (!client_) {
    return;
  }
  uint64_t requestId = 0;
  client_->unsubscribe(channel.c_str(), requestId);
  Track(RTM_ERROR_OK, "unsubscribe", requestId);
}

uint64_t RtmClient::Publish(const std::string& channel, const std::string& message) {
  if (!client_) {
    return 0;
  }
  PublishOptions options;
  uint64_t requestId = 0;
  client_->publish(channel.c_str(), message.data(), message.size(), options, requestId);
  return Track(RTM_ERROR_OK, "publish", requestId);
}

uint64_t RtmClient::GetOnlineUsers(const std::string& channel) {
  if (!client_ || !presence_) {
    return 0;
  }
  GetOnlineUsersOptions options;
  uint64_t requestId = 0;
  presence_->getOnlineUsers(channel.c_str(), RTM_CHANNEL_TYPE_MESSAGE, options, requestId);
  return Track(RTM_ERROR_OK, "getOnlineUsers", requestId);
}

uint64_t RtmClient::SetChannelMetadata(
    const std::string& channel,
    const std::vector<std::pair<std::string, std::string>>& items) {
  if (!client_ || !storage_) {
    return 0;
  }
  std::vector<std::string> keys;
  std::vector<std::string> values;
  keys.reserve(items.size());
  values.reserve(items.size());
  std::vector<MetadataItem> metadataItems;
  metadataItems.reserve(items.size());
  for (const auto& item : items) {
    keys.push_back(item.first);
    values.push_back(item.second);
  }
  for (size_t i = 0; i < keys.size(); ++i) {
    metadataItems.emplace_back(keys[i].c_str(), values[i].c_str());
  }

  Metadata data;
  data.items = metadataItems.empty() ? nullptr : metadataItems.data();
  data.itemCount = metadataItems.size();
  MetadataOptions options;
  options.recordTs = true;
  options.recordUserId = true;
  uint64_t requestId = 0;
  storage_->setChannelMetadata(channel.c_str(), RTM_CHANNEL_TYPE_MESSAGE, data, options, nullptr,
                               requestId);
  return Track(RTM_ERROR_OK, "setChannelMetadata", requestId);
}

uint64_t RtmClient::GetChannelMetadata(const std::string& channel) {
  if (!client_ || !storage_) {
    return 0;
  }
  uint64_t requestId = 0;
  storage_->getChannelMetadata(channel.c_str(), RTM_CHANNEL_TYPE_MESSAGE, requestId);
  return Track(RTM_ERROR_OK, "getChannelMetadata", requestId);
}

void RtmClient::Release() {
  IRtmClient* client = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    pending_.clear();
    client = client_;
    client_ = nullptr;
    storage_ = nullptr;
    presence_ = nullptr;
  }
  // 锁外释放：release 可能等待 SDK 回调，回调 Emit 需要同一把锁
  if (client) {
    client->release();
  }
}

// ---------- SDK 回调（工作线程） ----------

void RtmClient::onLoginResult(uint64_t requestId, RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  Emit(std::move(event));
}

void RtmClient::onLogoutResult(uint64_t requestId, RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  Emit(std::move(event));
}

void RtmClient::onSubscribeResult(uint64_t requestId, const char* /*channelName*/,
                                  RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  Emit(std::move(event));
}

void RtmClient::onUnsubscribeResult(uint64_t requestId, const char* /*channelName*/,
                                    RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  Emit(std::move(event));
}

void RtmClient::onPublishResult(uint64_t requestId, RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  Emit(std::move(event));
}

void RtmClient::onMessageEvent(const MessageEvent& event) {
  if (!event.message || !event.publisher) {
    return;
  }
  RtmEvent out;
  out.type = "message";
  out.publisher = event.publisher;
  out.message.assign(event.message, event.messageLength);
  Emit(std::move(out));
}

void RtmClient::onPresenceEvent(const PresenceEvent& event) {
  RtmEvent out;
  out.type = "presence";
  out.presence_type = static_cast<int>(event.type);
  out.publisher = event.publisher ? event.publisher : "";
  Emit(std::move(out));
}

void RtmClient::onConnectionStateChanged(const char* /*channelName*/, RTM_CONNECTION_STATE state,
                                         RTM_CONNECTION_CHANGE_REASON /*reason*/) {
  RtmEvent out;
  out.type = "connection";
  switch (state) {
    case RTM_CONNECTION_STATE_DISCONNECTED:
      out.reason = "disconnected";
      break;
    case RTM_CONNECTION_STATE_CONNECTING:
      out.reason = "connecting";
      break;
    case RTM_CONNECTION_STATE_CONNECTED:
      out.reason = "connected";
      break;
    case RTM_CONNECTION_STATE_RECONNECTING:
      out.reason = "reconnecting";
      break;
    case RTM_CONNECTION_STATE_FAILED:
      out.reason = "failed";
      break;
    default:
      out.reason = "unknown";
      break;
  }
  Emit(std::move(out));
}

void RtmClient::onGetOnlineUsersResult(uint64_t requestId, const UserState* userStateList,
                                       size_t count, const char* /*nextPage*/,
                                       RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  if (event.ok) {
    event.online_count = static_cast<int>(count);
    for (size_t i = 0; i < count; ++i) {
      const char* userId = userStateList ? userStateList[i].userId : nullptr;
      event.user_ids.emplace_back(userId ? userId : "");
    }
  }
  Emit(std::move(event));
}

void RtmClient::onSetChannelMetadataResult(uint64_t requestId, const char* /*channelName*/,
                                           RTM_CHANNEL_TYPE /*channelType*/,
                                           RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  Emit(std::move(event));
}

void RtmClient::onGetChannelMetadataResult(uint64_t requestId, const char* /*channelName*/,
                                           RTM_CHANNEL_TYPE /*channelType*/, const Metadata& data,
                                           RTM_ERROR_CODE errorCode) {
  RtmEvent event;
  event.type = "result";
  event.request_id = requestId;
  event.method = TakeMethod(requestId);
  event.ok = (errorCode == RTM_ERROR_OK);
  event.reason = ErrText(errorCode);
  if (event.ok) {
    event.major_revision = data.majorRevision;
    for (size_t i = 0; i < data.itemCount; ++i) {
      const MetadataItem& item = data.items[i];
      if (item.key && item.value) {
        event.metadata.emplace_back(item.key, item.value);
      }
    }
  }
  Emit(std::move(event));
}

}  // namespace himi_windows_rtm
