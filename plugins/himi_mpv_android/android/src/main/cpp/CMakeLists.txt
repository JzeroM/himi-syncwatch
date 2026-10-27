cmake_minimum_required(VERSION 3.10)
project(himi_mpv_android LANGUAGES CXX)

add_library(himi_mpv_android SHARED
    surface_jni.cpp)

find_library(log-lib log)
target_link_libraries(himi_mpv_android ${log-lib})
