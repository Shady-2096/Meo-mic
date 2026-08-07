#if !defined(_WIN32)

// POSIX shared memory, present so the frame bridge's concurrency logic can be
// tested on the development Mac (ADR 0006). It is not shipped anywhere — the
// product's only backend is Windows until ADR 0004 unblocks — but it is the
// reason the seqlock, the ring wrap, the validation, and both watchdogs have
// test coverage that actually runs.

#include "Mapping.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

namespace meo::detail {
namespace {

constexpr char kDefaultName[] = "Local\\MeoCamera.FrameBridge.v1";

// macOS caps POSIX shared-memory names at 31 characters including the leading
// slash (PSHMNAMLEN), which the Windows-shaped default blows straight past. So
// the name is hashed rather than truncated: truncation would collide two
// different bridges into one, and a collision here means one process's camera
// frames land in another's.
void ToShmName(const char* name, char* out, size_t out_size) {
  const char* source = (name != nullptr && *name != '\0') ? name : kDefaultName;

  uint64_t hash = 1469598103934665603ull;  // FNV-1a
  for (const char* p = source; *p != '\0'; ++p) {
    hash ^= static_cast<unsigned char>(*p);
    hash *= 1099511628211ull;
  }
  std::snprintf(out, out_size, "/meo.fb.%016llx",
                static_cast<unsigned long long>(hash));
}

}  // namespace

const char* Mapping::DefaultName() { return kDefaultName; }

Mapping::Mapping() = default;
Mapping::~Mapping() { Close(); }

bool Mapping::Create(const char* name, size_t bytes) {
  Close();
  ToShmName(name, shm_name_, sizeof(shm_name_));

  bool fresh = true;
  int fd = ::shm_open(shm_name_, O_CREAT | O_EXCL | O_RDWR, 0600);
  if (fd < 0) {
    // Left behind by an earlier run. Adopt it, matching the Win32 behaviour of
    // reusing an existing section rather than failing.
    fresh = false;
    fd = ::shm_open(shm_name_, O_RDWR, 0600);
    if (fd < 0) return false;
  } else {
    if (::ftruncate(fd, static_cast<off_t>(bytes)) != 0) {
      ::close(fd);
      ::shm_unlink(shm_name_);
      return false;
    }
  }

  void* view = ::mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (view == MAP_FAILED) {
    ::close(fd);
    if (fresh) ::shm_unlink(shm_name_);
    return false;
  }

  fd_ = fd;
  owner_ = true;
  data_ = view;
  size_ = bytes;
  created_fresh_ = fresh;
  return true;
}

bool Mapping::Open(const char* name, size_t bytes) {
  Close();
  ToShmName(name, shm_name_, sizeof(shm_name_));

  const int fd = ::shm_open(shm_name_, O_RDWR, 0600);
  if (fd < 0) return false;

  void* view = ::mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (view == MAP_FAILED) {
    ::close(fd);
    return false;
  }

  fd_ = fd;
  owner_ = false;
  data_ = view;
  size_ = bytes;
  created_fresh_ = false;
  return true;
}

void Mapping::Close() {
  if (data_ != nullptr) {
    ::munmap(data_, size_);
    data_ = nullptr;
  }
  if (fd_ >= 0) {
    ::close(fd_);
    fd_ = -1;
  }
  if (owner_ && shm_name_[0] != '\0') {
    ::shm_unlink(shm_name_);
  }
  owner_ = false;
  shm_name_[0] = '\0';
  size_ = 0;
  created_fresh_ = false;
}

}  // namespace meo::detail

#endif  // !_WIN32
