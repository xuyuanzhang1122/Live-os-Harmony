cmake_minimum_required(VERSION 3.5.0)
project(avcap)
add_library(avcap SHARED avcap.cpp)
target_link_libraries(avcap PUBLIC libace_napi.z.so libnative_media_codecbase.so libnative_media_core.so libnative_media_acodec.so)
