// Shared declarations for the Meo Windows virtual-camera feasibility probes.
//
// This code exists to answer two questions from CAMERA_BUILD_PLAN.md §18 and
// is deliberately throwaway. It is NOT the shape the product should take:
// there is no network, no frame bridge, no privacy slate, no error recovery.
// It draws a test pattern and nothing else.
//
//   Probe 1 (§18.1, §9.1) — which applications can enumerate a virtual camera
//     that exists ONLY as a Media Foundation software source? That answers
//     whether the DirectShow backend in §9.5 is mandatory work or optional.
//
//   Probe 3 (§18.3, §9.4) — can the Windows frame server, which runs under a
//     different account, activate a media source registered only under HKCU?
//     Or is HKLM registration (a one-time UAC prompt, permitted by C2)
//     required?

#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mferror.h>
#include <ks.h>
#include <ksmedia.h>
#include <ksproxy.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

// The CLSID of the probe media source. The host passes this same GUID, in
// string form, to MFCreateVirtualCamera as the source id, and the frame
// server CoCreateInstances it out of whichever registry hive the probe
// registered into.
//
// {0B914DE5-CF52-4F35-B43D-104314D226D1}
extern "C" const GUID CLSID_MeoProbeSource;

namespace meo {

// One format only. The plan (§9.4, §8.3) settles on NV12, and a probe that
// advertises a single format removes format negotiation as a variable when an
// application fails to show the camera.
inline constexpr UINT32 kWidth = 1280;
inline constexpr UINT32 kHeight = 720;
inline constexpr UINT32 kFrameRate = 30;
inline constexpr LONGLONG kFrameDuration100ns = 10'000'000LL / kFrameRate;

// §1.1: Windows appends its own suffix to whatever friendly name is supplied.
// Recording the exact rendered string is part of what Probe 1 must report, so
// the name here is deliberately the one the product would use.
inline constexpr wchar_t kFriendlyName[] = L"Meo Camera Probe";

// NV12 is 12 bits per pixel: a full-resolution Y plane followed by an
// interleaved, half-resolution UV plane.
inline constexpr DWORD kFrameBytes = kWidth * kHeight * 3 / 2;

// Writes one NV12 test frame. The pattern has to make three failure modes
// visible at a glance in a meeting app's preview:
//
//   - a frozen image      -> the sweep bar stops moving
//   - a torn/short buffer -> the colour bars break up
//   - a stride mistake    -> the bars skew diagonally
//
// `frameIndex` drives the animation; `stride` is the destination Y-plane
// stride in bytes, which is not always equal to the width.
void WriteTestFrame(BYTE* dest, LONG stride, UINT64 frameIndex);

// Formats an HRESULT as "0x80070005 (Access is denied)" for the probe log.
// Every question these probes ask is answered by a specific failure code, so
// the codes have to survive to the report rather than collapsing into
// "it didn't work".
std::wstring FormatHresult(HRESULT hr);

// Probe output goes to both the console and the debugger, because when the
// frame server loads this DLL there is no console to print to — DebugView or
// the Visual Studio output window is the only way to see it.
void ProbeLog(const wchar_t* format, ...);

}  // namespace meo
