// tis-reenable.c — 强制 Squirrel 输入源走完整"禁用→启用→选中"路径。
//
// 背景：macOS 26 上系统设置/输入菜单的输入法列表读 com.apple.HIToolbox 的
// AppleEnabledInputSources；当 TIS 数据库已认为源 enabled 时，单纯的
// TISEnableInputSource 是 no-op，不会补写 plist——表现是"打字一切正常，
// 但设置和列表里看不到鼠须管"。先禁用再启用可强制走完整路径，把源同步
// 回 plist。幂等；禁用瞬间当前源会短暂跳到其他键盘布局，随后立即选回。
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  CFArrayRef list = TISCreateInputSourceList(NULL, true);
  CFIndex n = CFArrayGetCount(list);
  TISInputSourceRef hans = NULL, parent = NULL;
  for (CFIndex i = 0; i < n; i++) {
    TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
    CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
    if (!id) continue;
    char buf[128] = {0};
    if (!CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8)) continue;
    if (strcmp(buf, "im.rime.inputmethod.Squirrel.Hans") == 0) hans = s;
    if (strcmp(buf, "im.rime.inputmethod.Squirrel") == 0) parent = s;
  }
  if (!hans) { printf("未找到 Squirrel.Hans\n"); return 1; }

  printf("disable  -> %d\n", (int)TISDisableInputSource(hans));
  printf("enable   -> %d\n", (int)TISEnableInputSource(hans));
  if (parent) printf("enable父 -> %d\n", (int)TISEnableInputSource(parent));
  OSStatus sel = TISSelectInputSource(hans);
  printf("select   -> %d\n", (int)sel);

  TISInputSourceRef cur = TISCopyCurrentKeyboardInputSource();
  if (cur) {
    CFStringRef id = (CFStringRef)TISGetInputSourceProperty(cur, kTISPropertyInputSourceID);
    char buf[128] = {0};
    if (id) CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8);
    printf("当前源: %s\n", buf);
    CFRelease(cur);
  }
  CFRelease(list);
  return sel == noErr ? 0 : 2;
}
