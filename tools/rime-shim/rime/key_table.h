// librime 1.17.0 的 rime/key_table.h（本机 librime 源码未 checkout，此处按上游 1.17.0 原样补齐，
// 仅用于编译 Squirrel；内容与已安装 librime.1.dylib 的 ABI 一致）。
#ifndef RIME_KEY_TABLE_H_
#define RIME_KEY_TABLE_H_

#include <X11/keysym.h>
#include <rime_api.h>

typedef enum {
  kShiftMask = 1 << 0,
  kLockMask = 1 << 1,
  kControlMask = 1 << 2,
  kMod1Mask = 1 << 3,
  kAltMask = kMod1Mask,
  kMod2Mask = 1 << 4,
  kMod3Mask = 1 << 5,
  kMod4Mask = 1 << 6,
  kMod5Mask = 1 << 7,
  kButton1Mask = 1 << 8,
  kButton2Mask = 1 << 9,
  kButton3Mask = 1 << 10,
  kButton4Mask = 1 << 11,
  kButton5Mask = 1 << 12,

  /* The next few modifiers are used by XKB, so we skip to the end.
   * Bits 15 - 23 are currently unused. Bit 29 is used internally.
   */

  /* ibus :) mask */
  kHandledMask = 1 << 24,
  kForwardMask = 1 << 25,
  kIgnoredMask = kForwardMask,

  kSuperMask = 1 << 26,
  kHyperMask = 1 << 27,
  kMetaMask = 1 << 28,

  kReleaseMask = 1 << 30,

  kModifierMask = 0x5f001fff
} RimeModifier;

#ifdef __cplusplus
extern "C" {
#endif

RIME_DLL int RimeGetModifierByName(const char* name);
RIME_DLL const char* RimeGetModifierName(int modifier);
RIME_DLL int RimeGetKeycodeByName(const char* name);
RIME_DLL const char* RimeGetKeyName(int keycode);

#ifdef __cplusplus
}
#endif

#endif  // RIME_KEY_TABLE_H_
