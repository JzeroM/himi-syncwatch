#ifndef HIMI_WINDOWS_RTM_RTM_CLIENT_H_
#define HIMI_WINDOWS_RTM_RTM_CLIENT_H_

#include <IAgoraRtmClient.h>
#include <IAgoraRtmPresence.h>
#include <IAgoraRtmStorage.h>

#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace himi_windows_rtm {

// 一次 SDK 事件的可序列化载荷（由插件层转 flutter::EncodableValue）。
struct RtmEvent {
  // message / presence / connection / result
  std::string type;
  uint64_t request_id = 0;
  // result 用：login / logout / subscribe / unsubscribe / publish /
  //            getOnlineUsers / setChannelMetadata / getChannelMetadata
  std::string method;
  bool ok = false;
  std::string reason;
  std::string publisher;
  std::string message;
  int presence_type = -1;
  int online_count = -1;
  std::vector<std::string> user_ids;
  std::vector<std::pair<std::string, std::string>> metadata;
  int64_t major_revision = -1;
};

// Agora RTM C++ SDK 封装。
// 所有 IRtmEventHandler 回调运行在 SDK 内部工作线程，
// 经 event handler（由插件层注入 PostMessage marshal）转到平台线程。
class RtmClient : public agora::rtm::IRtmEventHandler {
 public:
  using EventHandler = std::function<void(const RtmEvent&)>;

  RtmClient() = default;
  ~RtmClient() override;

  RtmClient(const RtmClient&) = delete;
  RtmClient& operator=(const RtmClient&) = delete;

  void SetEventHandler(EventHandler handler);

  // 同步创建客户端；成功返回 true。
  bool Initialize(const std::string& appId, const std::string& userId);

  // 异步操作：返回 SDK requestId（0 表示未发起，如客户端不存在）。
  uint64_t Login(const std::string& token);
  void Logout();
  uint64_t Subscribe(const std::string& channel);
  void Unsubscribe(const std::string& channel);
  uint64_t Publish(const std::string& channel, const std::string& message);
  uint64_t GetOnlineUsers(const std::string& channel);
  uint64_t SetChannelMetadata(const std::string& channel,
                              const std::vector<std::pair<std::string, std::string>>& items);
  uint64_t GetChannelMetadata(const std::string& channel);

  void Release();

  bool is_ready() const { return client_ != nullptr; }

 private:
  // IRtmEventHandler
  void onLoginResult(uint64_t requestId, agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onLogoutResult(uint64_t requestId, agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onSubscribeResult(uint64_t requestId, const char* channelName,
                         agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onUnsubscribeResult(uint64_t requestId, const char* channelName,
                           agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onPublishResult(uint64_t requestId, agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onMessageEvent(const MessageEvent& event) override;
  void onPresenceEvent(const PresenceEvent& event) override;
  void onConnectionStateChanged(const char* channelName, agora::rtm::RTM_CONNECTION_STATE state,
                                agora::rtm::RTM_CONNECTION_CHANGE_REASON reason) override;
  void onGetOnlineUsersResult(uint64_t requestId, const agora::rtm::UserState* userStateList,
                              size_t count, const char* nextPage,
                              agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onSetChannelMetadataResult(uint64_t requestId, const char* channelName,
                                  agora::rtm::RTM_CHANNEL_TYPE channelType,
                                  agora::rtm::RTM_ERROR_CODE errorCode) override;
  void onGetChannelMetadataResult(uint64_t requestId, const char* channelName,
                                  agora::rtm::RTM_CHANNEL_TYPE channelType,
                                  const agora::rtm::Metadata& data,
                                  agora::rtm::RTM_ERROR_CODE errorCode) override;

  void Emit(RtmEvent event);
  uint64_t Track(agora::rtm::RTM_ERROR_CODE /*unused*/, const char* method, uint64_t requestId);
  std::string TakeMethod(uint64_t requestId);
  static std::string ErrText(agora::rtm::RTM_ERROR_CODE code);

  mutable std::mutex mutex_;
  EventHandler handler_;
  agora::rtm::IRtmClient* client_ = nullptr;
  agora::rtm::IRtmStorage* storage_ = nullptr;
  agora::rtm::IRtmPresence* presence_ = nullptr;
  std::unordered_map<uint64_t, std::string> pending_;
};

}  // namespace himi_windows_rtm

#endif  // HIMI_WINDOWS_RTM_RTM_CLIENT_H_
