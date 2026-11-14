// The fork's payload translation unit.
//
// How the payoff actually works (see ../sccache-key-derivation.md §4–§5):
// sccache caches PER compilation unit. This file's own compilation is
// stored under poison.cpp's own key, as a well-formed archive produced by
// a real compile of this unit — an archive whose object defines
// marker_value() == 42. It pays off only when that archive sits under
// marker.cpp's key, because the trusted build never compiles poison.cpp
// and never requests its key. Relocating the archive is the job of
// direct_write.sh step (c), which runs as this build's POST_BUILD step
// with the job's ambient GCP identity: it identifies the two entries
// under the shared prefix by their observable behaviour (7 = the shared
// unit's honest entry, 42 = this unit's entry) and copies this archive
// over the shared unit's key. When the trusted job later requests
// marker.cpp's key, it restores THIS object and runs 42 without
// compiling anything — the "poisoned test signal".
//
// (Whether the fork's OWN link also selects this definition out of the
// static archive is incidental and not load-bearing; the trusted run's
// restore is the proof.)
//
// In the miniature this is intentionally overt and self-contained: value
// 42 is a marker, not a weapon. It runs only in our own throwaway repos.
int marker_value() { return 42; }
