// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/application.hpp"
#include "host/logging.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>

#include <crtdbg.h>
#include <cstdlib>
#include <exception>
#include <string>
#include <vector>

namespace {

bool valid_standard_handle(DWORD identifier) {
    const HANDLE handle = GetStdHandle(identifier);
    if (handle == nullptr || handle == INVALID_HANDLE_VALUE) return false;
    DWORD flags = 0U;
    return GetHandleInformation(handle, &flags) != FALSE;
}

bool requests_cli_console(const std::vector<std::wstring>& arguments) {
    for (const std::wstring& argument : arguments) {
        if (argument == L"--help" || argument == L"--self-test" ||
            argument.starts_with(L"--self-test=")) {
            return true;
        }
    }
    return false;
}

void prepare_console(bool cli_mode) {
    if (valid_standard_handle(STD_OUTPUT_HANDLE) ||
        valid_standard_handle(STD_ERROR_HANDLE)) {
        return;
    }
    if (AttachConsole(ATTACH_PARENT_PROCESS) == FALSE && cli_mode) {
        (void)AllocConsole();
    }
    if (GetConsoleOutputCP() != 0U) {
        (void)SetConsoleOutputCP(CP_UTF8);
    }
}

void disable_interactive_failure_ui() {
    (void)SetErrorMode(
        SEM_FAILCRITICALERRORS |
        SEM_NOGPFAULTERRORBOX |
        SEM_NOOPENFILEERRORBOX);
    _set_abort_behavior(0U, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#if defined(_DEBUG)
    (void)_CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_DEBUG);
    (void)_CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_DEBUG);
#endif
}

std::vector<std::wstring> command_line_arguments() {
    int count = 0;
    LPWSTR* raw = CommandLineToArgvW(GetCommandLineW(), &count);
    if (raw == nullptr || count <= 0) {
        return {L"kzmrecomp_host"};
    }
    std::vector<std::wstring> arguments;
    arguments.reserve(static_cast<std::size_t>(count));
    for (int index = 0; index < count; ++index) {
        arguments.emplace_back(raw[index]);
    }
    LocalFree(raw);
    return arguments;
}

} // namespace

int WINAPI wWinMain(
    HINSTANCE,
    HINSTANCE,
    PWSTR,
    int) {
    disable_interactive_failure_ui();
    const std::vector<std::wstring> arguments = command_line_arguments();
    prepare_console(requests_cli_console(arguments));
    kzm::host::Logger logger;
    try {
        return kzm::host::run_application(arguments, logger);
    } catch (const std::exception& error) {
        logger.log(
            kzm::host::LogLevel::error,
            "unhandled_failure",
            error.what(),
            {{"exit_code", "70"}});
        return 70;
    } catch (...) {
        logger.log(
            kzm::host::LogLevel::error,
            "unhandled_failure",
            "unknown host failure",
            {{"exit_code", "70"}});
        return 70;
    }
}
