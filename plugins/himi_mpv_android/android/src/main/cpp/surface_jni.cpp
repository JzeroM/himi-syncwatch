#include <jni.h>
#include <cstdint>

extern "C" JNIEXPORT jlong JNICALL
Java_com_himi_mpv_android_HimiMpvSurfaceView_nativeCreateGlobalRef(
    JNIEnv* env, jobject /*thiz*/, jobject surface) {
  if (surface == nullptr) return 0;
  return reinterpret_cast<jlong>(env->NewGlobalRef(surface));
}

extern "C" JNIEXPORT void JNICALL
Java_com_himi_mpv_android_HimiMpvSurfaceView_nativeDeleteGlobalRef(
    JNIEnv* env, jobject /*thiz*/, jlong ref) {
  if (ref != 0) {
    env->DeleteGlobalRef(reinterpret_cast<jobject>(ref));
  }
}
