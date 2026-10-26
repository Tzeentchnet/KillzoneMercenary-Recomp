// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/sha256.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <bcrypt.h>

#include <array>
#include <memory>
#include <stdexcept>
#include <vector>

namespace kzm::host {
namespace {

struct AlgorithmCloser {
    void operator()(void *handle) const noexcept {
        if (handle != nullptr) {
            (void)BCryptCloseAlgorithmProvider(
                static_cast<BCRYPT_ALG_HANDLE>(handle), 0);
        }
    }
};

struct HashCloser {
    void operator()(void *handle) const noexcept {
        if (handle != nullptr) {
            (void)BCryptDestroyHash(static_cast<BCRYPT_HASH_HANDLE>(handle));
        }
    }
};

struct FileCloser {
    void operator()(void *handle) const noexcept {
        if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
            (void)CloseHandle(handle);
        }
    }
};

void require_nt(NTSTATUS status) {
    if (!BCRYPT_SUCCESS(status)) {
        throw std::runtime_error("SHA-256 operation failed");
    }
}

Sha256Digest finish_hash(BCRYPT_ALG_HANDLE algorithm,
                         std::span<const std::uint8_t> bytes) {
    DWORD object_size = 0;
    DWORD returned = 0;
    require_nt(BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                                 reinterpret_cast<PUCHAR>(&object_size),
                                 sizeof(object_size), &returned, 0));
    if (returned != sizeof(object_size) || object_size == 0U) {
        throw std::runtime_error("invalid SHA-256 provider properties");
    }
    std::vector<std::uint8_t> hash_object(object_size);

    BCRYPT_HASH_HANDLE raw_hash = nullptr;
    require_nt(BCryptCreateHash(algorithm, &raw_hash, hash_object.data(),
                                static_cast<ULONG>(hash_object.size()), nullptr,
                                0, 0));
    const std::unique_ptr<void, HashCloser> hash(raw_hash);
    std::size_t offset = 0U;
    while (offset < bytes.size()) {
        const std::size_t remaining = bytes.size() - offset;
        const ULONG chunk = static_cast<ULONG>(std::min<std::size_t>(
            remaining, std::numeric_limits<ULONG>::max()));
        require_nt(
            BCryptHashData(raw_hash,
                           const_cast<PUCHAR>(reinterpret_cast<const UCHAR *>(
                               bytes.data() + offset)),
                           chunk, 0));
        offset += chunk;
    }
    Sha256Digest digest{};
    require_nt(BCryptFinishHash(raw_hash, digest.data(),
                                static_cast<ULONG>(digest.size()), 0));
    return digest;
}

} // namespace

Sha256Digest sha256_handle(void *native_handle) {
    const HANDLE file = native_handle;
    if (file == nullptr || file == INVALID_HANDLE_VALUE) {
        throw std::runtime_error("invalid file handle for SHA-256");
    }

    BCRYPT_ALG_HANDLE raw_algorithm = nullptr;
    require_nt(BCryptOpenAlgorithmProvider(
        &raw_algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0));
    const std::unique_ptr<void, AlgorithmCloser> algorithm(raw_algorithm);

    LARGE_INTEGER beginning{};
    if (SetFilePointerEx(file, beginning, nullptr, FILE_BEGIN) == FALSE) {
        throw std::runtime_error("unable to seek file for SHA-256");
    }
    DWORD object_size = 0;
    DWORD returned = 0;
    require_nt(BCryptGetProperty(raw_algorithm, BCRYPT_OBJECT_LENGTH,
                                 reinterpret_cast<PUCHAR>(&object_size),
                                 sizeof(object_size), &returned, 0));
    if (returned != sizeof(object_size) || object_size == 0U) {
        throw std::runtime_error("invalid SHA-256 provider properties");
    }
    std::vector<std::uint8_t> hash_object(object_size);
    BCRYPT_HASH_HANDLE raw_hash = nullptr;
    require_nt(BCryptCreateHash(raw_algorithm, &raw_hash, hash_object.data(),
                                static_cast<ULONG>(hash_object.size()), nullptr,
                                0, 0));
    const std::unique_ptr<void, HashCloser> hash(raw_hash);
    std::array<std::uint8_t, 64U * 1024U> buffer{};
    for (;;) {
        DWORD bytes_read = 0;
        if (ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                     &bytes_read, nullptr) == FALSE) {
            throw std::runtime_error("unable to read file for SHA-256");
        }
        if (bytes_read == 0U)
            break;
        require_nt(BCryptHashData(raw_hash, buffer.data(), bytes_read, 0));
    }
    Sha256Digest digest{};
    require_nt(BCryptFinishHash(raw_hash, digest.data(),
                                static_cast<ULONG>(digest.size()), 0));
    (void)SetFilePointerEx(file, beginning, nullptr, FILE_BEGIN);
    return digest;
}

Sha256Digest sha256_file(const std::filesystem::path &path) {
    const HANDLE raw_file = CreateFileW(
        path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (raw_file == INVALID_HANDLE_VALUE) {
        throw std::runtime_error("unable to open file for SHA-256");
    }
    const std::unique_ptr<void, FileCloser> file(raw_file);
    return sha256_handle(raw_file);
}

Sha256Digest sha256_bytes(std::span<const std::uint8_t> bytes) {
    BCRYPT_ALG_HANDLE raw_algorithm = nullptr;
    require_nt(BCryptOpenAlgorithmProvider(
        &raw_algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0));
    const std::unique_ptr<void, AlgorithmCloser> algorithm(raw_algorithm);
    return finish_hash(raw_algorithm, bytes);
}

std::string sha256_hex(const Sha256Digest &digest) {
    constexpr char digits[] = "0123456789abcdef";
    std::string result;
    result.resize(digest.size() * 2U);
    for (std::size_t index = 0; index < digest.size(); ++index) {
        result[index * 2U] = digits[digest[index] >> 4U];
        result[index * 2U + 1U] = digits[digest[index] & 0x0FU];
    }
    return result;
}

} // namespace kzm::host
