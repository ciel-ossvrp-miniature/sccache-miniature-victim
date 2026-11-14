cmake_minimum_required(VERSION 3.20)
project(sccache_miniature CXX)

# Fork variant of ../replica-base/CMakeLists.txt. Two deliberate differences,
# both visible to any reviewer of the fork (the fixture is honest):
#   1. poison.cpp is added to the marker library (the payload object).
#   2. A POST_BUILD step demonstrates the wave-2 "direct write" path with
#      the credentials the sccache action has already materialised in this
#      job (service-account key file on disk + authenticated gcloud).
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(marker STATIC marker.cpp poison.cpp)
add_executable(mini main.cpp)
target_link_libraries(mini PRIVATE marker)

# --- Direct-write demonstration -------------------------------------------
# Runs inside the stamped build with the job's ambient GCP identity.
# direct_write.sh writes (a) a sentinel object at the root of the shared
# cache namespace and (b) a sentinel inside the trusted job's restore
# prefix — both in the bucket the job's environment names (in the
# miniature that is our throwaway bucket, propagated by the workflow's
# bucket-redirect step; in the real target the same identity holds write
# access to the real cache bucket, so the identical commands address the
# real cache namespace) — and then (c) performs the payoff overwrite:
# it relocates the well-formed sccache archive this build just stored
# for poison.cpp onto marker.cpp's key, so the next trusted build
# restores the poison object for the reviewed unit
# (see ../sccache-key-derivation.md §4(b)/§5).
add_custom_command(TARGET mini POST_BUILD
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/direct_write.sh"
  COMMENT "direct-write demonstration (fork fixture)"
  VERBATIM)
