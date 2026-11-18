/*
 * Copyright (c) 2023-2026 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>
//#include <vulkan/vulkan.h> // before any mdk header
#include <mdk/Player.h>
#include <mdk/MediaInfo.h>
#include <cassert>
#include <unordered_map>
#include <iostream>
#include <sys/system_properties.h>

using namespace std;

class TexturePlayer final : public mdk::Player
{
public:
    TexturePlayer(jlong handle)
        : mdk::Player(reinterpret_cast<mdkPlayerAPI*>(handle))
    {
        handleId = handle;
    }

    int width = 0;
    int height = 0;
    jobject surface = nullptr;
    void* vo_opaque = nullptr; // can change by TextureRegistry.SurfaceProducer.Callback
    bool directSurface = false; // decoder renders into the surface, no GL renderer
    // Dart 侧创建并拥有 mdkPlayerAPI（mdkPlayerAPI_new/Delete）。本包装非拥有
    //（owner_=false），析构 ~Player()→mdkPlayerAPI_reset(&p, false) 会对**存活
    // 的 player** reset callbacks（触碰它）。故 erase（触发 ~TexturePlayer）必须
    // 先于 Dart 的 mdkPlayerAPI_delete，否则 reset 作用在已释放对象 → SIGSEGV。
    // 记录 Dart 传入的 handle，供 nativeDetachPlayer 按 handle 反查本表项。
    jlong handleId = 0;
private:
};

static unordered_map<int64_t, shared_ptr<TexturePlayer>> players;


extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    clog << "JNI_OnLoad" << endl;
    mdk::javaVM(vm);
    mdk::SetGlobalOption("profiler.gpu", 1);

    JNIEnv *env = nullptr;
    if (vm->GetEnv((void **) &env, JNI_VERSION_1_4) != JNI_OK || !env) {
        clog << "GetEnv for JNI_VERSION_1_4 failed" << endl;
        return -1;
    }

    return JNI_VERSION_1_4;
}

void JNI_OnUnload(JavaVM *vm, void *reserved) {
    clog << "JNI_OnUnload" << endl;
}
}

extern "C"
JNIEXPORT void JNICALL
Java_com_mediadevkit_fvp_FvpPlugin_nativeSetSurface(JNIEnv *env, jobject thiz, jlong player_handle,
                                                    jlong tex_id, jobject surface, jint w, jint h, jboolean tunnel) {
    if (!player_handle || !surface) {
        if (auto it = players.find(tex_id); it != players.end()) {
            auto& player = it->second;
            auto s = player->surface;
            if (player->directSurface) {
                // Release the codec BEFORE the surface dies, or it wedges
                // (dequeue -10000) and the stream is marked decode-error, so
                // the next surface never shows a frame. Empty list, not a
                // surface-less re-open: that costs ~600ms of codec restart
                // and pipeline re-prime, here on the UI thread inside
                // surfaceDestroyed.
                player->setDecoders(mdk::MediaType::Video, {});
            }
            player->updateNativeSurface(nullptr);
            players.erase(it);
            if (s) {
                env->DeleteGlobalRef(s);
            }
        } else {
            clog << "player not found(already removed?) for textureId " + std::to_string(tex_id) + " surface " + std::to_string((intptr_t)surface) << endl;
        }
        return;
    }
    assert(surface && "null surface");
    auto player = make_shared<TexturePlayer>(player_handle);
    clog << __func__ << endl;
    if (tunnel) {
        // MediaCodec writes into the surface's buffer queue itself: no GL
        // renderer, no EGLConfig, no GPU copy. image=0 drops the AImageReader
        // readback path; dv=1 is needed for Dolby Vision profile 5 on older
        // SDKs. The surface only exists after prepare(), so setDecoders is
        // what forces the re-open that makes it take effect.
        player->surface = env->NewGlobalRef(surface);
        player->directSurface = true;
        player->setDecoders(mdk::MediaType::Video,
            {"AMediaCodec:dv=1:image=0:surface=" + std::to_string((intptr_t)player->surface)});
    } else {
        player->surface = env->NewGlobalRef(surface);
        player->updateNativeSurface(player->surface, w, h);
        player->vo_opaque = player->surface;
    }
    player->width = w;
    player->height = h;
    players[tex_id] = player;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_mediadevkit_fvp_FvpPlugin_nativeSetSurfaceSize(JNIEnv *env, jobject thiz, jlong tex_id,
                                                        jint w, jint h) {
    auto it = players.find(tex_id);
    if (it == players.end()) {
        return;
    }
    auto& player = it->second;
    player->width = w;
    player->height = h;
    // Only the GL renderer draws at the surface size; with tunnel the decoder
    // owns the geometry and the compositor scales its layer.
    if (!player->directSurface && player->surface) {
        player->updateNativeSurface(player->surface, w, h);
    }
}

// 694 闪退根治：Dart 销毁引擎前**强制**按 handle 反查并擦除本表项（触发
// ~TexturePlayer→mdkPlayerAPI_reset(&p,false) 在**存活 player** 上 reset
// callbacks），再走 mdkPlayerAPI_delete 才安全。surfaceView 输出（TV 默认）
// 的 erase 由 FvpVideoView.dispose()/surfaceDestroyed 驱动，时机是 Flutter
// 平台视图生命周期（异步、可能晚于 Dart delete）→ 若 delete 后才 erase，
// reset 触碰已释放 player → SIGSEGV。此函数把 erase 提到 delete 前并 await，
// 之后迟到的 surfaceDestroyed 查无此 player 走 "player not found" 安全 no-op。
extern "C"
JNIEXPORT void JNICALL
Java_com_mediadevkit_fvp_FvpPlugin_nativeDetachPlayer(JNIEnv *env, jobject thiz, jlong player_handle) {
    for (auto it = players.begin(); it != players.end(); ) {
        auto& player = it->second;
        if (player && player->handleId == player_handle) {
            auto s = player->surface;
            if (player->directSurface) {
                // 释放 codec 必须在 surface 死前，否则 dequeue 卡死、标记 decode-error。
                player->setDecoders(mdk::MediaType::Video, {});
            }
            player->updateNativeSurface(nullptr);
            player->surface = nullptr;
            // erase → shared_ptr 归零 → ~TexturePlayer（在存活 player 上 reset）。
            it = players.erase(it);
            if (s) {
                env->DeleteGlobalRef(s);
            }
        } else {
            ++it;
        }
    }
}

extern "C"
JNIEXPORT bool JNICALL
MdkIsEmulator()
{
    // run getprop to see all properties
    char v[PROP_VALUE_MAX+1];
    __system_property_get("ro.kernel.qemu", v);
    if (atoi(v) == 1)
        return true;
    __system_property_get("ro.boot.qemu", v);
    if (atoi(v) == 1)
        return true;
    __system_property_get("ro.product.board", v);
    if (strstr(v, "goldfish"))
        return true;
    __system_property_get("ro.hardware.egl", v);
    if (strstr(v, "emulation"))
        return true;
    __system_property_get("ro.hardware", v);
    if (strstr(v, "ranchu"))
        return true;
    __system_property_get("ro.build.characteristics", v);
    if (strstr(v, "emulator"))
        return true;
    return false;
}

extern "C"
JNIEXPORT void* JNICALL
MdkGetPlayerVid(int64_t tex_id)
{
    if (tex_id < 0)
        return nullptr;
    if (const auto it = players.find(tex_id); it != players.end()) {
        const auto& player = it->second;
        return player->vo_opaque;
    }
    return nullptr;
}