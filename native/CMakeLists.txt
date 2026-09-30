cmake_minimum_required(VERSION 3.10)
project(violin_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(violin_engine SHARED
    audio_processor.cpp
    ffi_bridge.cpp
)

target_include_directories(violin_engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

if (ANDROID)
    target_link_libraries(violin_engine
        log
        android
        aaudio
    )
endif()
