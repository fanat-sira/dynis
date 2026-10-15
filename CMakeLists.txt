cmake_minimum_required(VERSION 3.16)
project(Dynis VERSION 1.0.12 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Network DBus Test Concurrent)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-unix-2.0)
find_library(UDEV_LIB NAMES udev REQUIRED)

add_executable(lyricsmpris
    lyricsmpris/main.cpp
    lyricsmpris/CjkVariantNormalizer.h
    lyricsmpris/CjkVariantNormalizer.cpp
    lyricsmpris/LyricsCore.h
    lyricsmpris/LyricsCore.cpp
    lyricsmpris/LyricsMprisApp.h
    lyricsmpris/LyricsMprisApp.cpp
)

target_include_directories(lyricsmpris PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/lyricsmpris
)

target_link_libraries(lyricsmpris PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::DBus
)

enable_testing()

add_executable(lyricsmpris_tests
    tests/lyricsmpris_core_tests.cpp
    lyricsmpris/CjkVariantNormalizer.h
    lyricsmpris/CjkVariantNormalizer.cpp
    lyricsmpris/LyricsCore.h
    lyricsmpris/LyricsCore.cpp
)

target_include_directories(lyricsmpris_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/lyricsmpris
)

target_link_libraries(lyricsmpris_tests PRIVATE
    Qt6::Core
    Qt6::Test
)

add_test(NAME lyricsmpris_core COMMAND lyricsmpris_tests)

add_executable(user_config_backend_tests
    tests/user_config_backend_tests.cpp
    backend/UserConfigBackend.h
    backend/UserConfigBackend.cpp
)

target_include_directories(user_config_backend_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/backend
)

target_link_libraries(user_config_backend_tests PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Test
)

add_test(NAME user_config_backend COMMAND user_config_backend_tests)

add_executable(dynis-setup
    tools/dynis-setup.cpp
)

target_link_libraries(dynis-setup PRIVATE
    Qt6::Core
)

add_executable(launcher_backend_tests
    tests/launcher_backend_tests.cpp
    backend/LauncherBackend.h
    backend/LauncherBackend.cpp
)
target_include_directories(launcher_backend_tests PRIVATE backend)
target_link_libraries(launcher_backend_tests PRIVATE Qt6::Core Qt6::Qml Qt6::Test PkgConfig::GIO)
add_test(NAME launcher_backend COMMAND launcher_backend_tests)

add_executable(setup_tests tests/setup_tests.cpp)
target_link_libraries(setup_tests PRIVATE Qt6::Core Qt6::Test)
add_test(NAME setup COMMAND setup_tests)

# Main Backend Module (Combining all C++ components)
qt_add_qml_module(DynisBackend
    URI DynisBackend
    VERSION 1.0
    SOURCES
        backend/LauncherBackend.h
        backend/LauncherBackend.cpp
        backend/ConfigMigration.h
        backend/SysBackend.h
        backend/SysBackend.cpp
        backend/SystemServices.h
        backend/SystemServices.cpp
        backend/StyleTokensBackend.h
        backend/StyleTokensBackend.cpp
        backend/UserConfigBackend.h
        backend/UserConfigBackend.cpp
        backend/BluetoothPairingAgent.h
        backend/BluetoothPairingAgent.cpp
        backend/WifiController.h
        backend/WifiController.cpp
        backend/WifiNetworkModel.h
        backend/WifiNetworkModel.cpp
)

target_include_directories(DynisBackend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/backend
)

target_link_libraries(DynisBackend PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Network
    Qt6::DBus
    Qt6::Concurrent
    PkgConfig::GIO
    ${UDEV_LIB}
)

# Installation Rules
include(GNUInstallDirs)

# Install Quickshell entry points and QML component folders to /usr/share/dynis
install(FILES
    shell.qml
    DynamicIslandWindow.qml
    LauncherWindow.qml
    IslandGlassCarrier.qml
    WorkspaceIslandWindow.qml
    RoundedScreenCornersWindow.qml
    DESTINATION ${CMAKE_INSTALL_DATADIR}/dynis
)
install(DIRECTORY qml
    DESTINATION ${CMAKE_INSTALL_DATADIR}/dynis
    FILES_MATCHING PATTERN "*.qml" PATTERN "*.qsb"
)

# Ship the visual font set used by the default Dynis configuration.
install(DIRECTORY fonts/
    DESTINATION ${CMAKE_INSTALL_DATADIR}/fonts/dynis
    FILES_MATCHING PATTERN "*.ttf"
)

# Install DynisBackend backing library to /usr/lib
install(TARGETS DynisBackend
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

# Install DynisBackend plugin to Qt6 QML directory
install(TARGETS DynisBackendplugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/DynisBackend
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install qmldir and other generated files for DynisBackend
install(FILES 
    ${CMAKE_CURRENT_BINARY_DIR}/qmldir
    ${CMAKE_CURRENT_BINARY_DIR}/DynisBackend.qmltypes
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/DynisBackend
)


# Install launcher
install(PROGRAMS dynis-launcher DESTINATION ${CMAKE_INSTALL_BINDIR} RENAME dynis)

# Install helper executables
install(TARGETS lyricsmpris
    RUNTIME DESTINATION ${CMAKE_INSTALL_DATADIR}/dynis/bin
)
install(TARGETS dynis-setup
    RUNTIME DESTINATION ${CMAKE_INSTALL_DATADIR}/dynis/bin
)

# Install desktop entry
install(FILES dynis.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# Install systemd user service (substitute ExecStart with actual install prefix)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/dynis.service.in
    ${CMAKE_CURRENT_BINARY_DIR}/dynis.service
    @ONLY
)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/dynis.service DESTINATION /usr/lib/systemd/user)

add_executable(system_services_tests tests/system_services_tests.cpp)
target_include_directories(system_services_tests PRIVATE backend)
target_link_libraries(system_services_tests PRIVATE DynisBackend Qt6::Core Qt6::Test)
add_test(NAME system_services COMMAND system_services_tests)
