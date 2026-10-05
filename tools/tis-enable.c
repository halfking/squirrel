// tis-enable.c — 通过 TIS 正路启用并选中 Squirrel 输入源。
//
// 为什么不能直接写 AppleEnabledInputSources：
// TextInputMenuAgent 持有该 plist 的内存态，任何偏好变更都会让它把自己的
// 状态回写覆盖，手工写入会在下一次刷新时丢失。走 TISEnableInputSource /
// TISSelectInputSource 则是系统认可的路径，各方状态自动保持一致。
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>
#include <objc/message.h>

static void dumpProps(TISInputSourceRef src) {
  CFStringRef id = (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
  CFStringRef name = (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyLocalizedName);
  // enable_status 是 CFNumber，不是 Boolean
  CFTypeRef st = TISGetInputSourceProperty(src, CFSTR("EnableStatus"));
  int enabled = -1;
  if (st && CFGetTypeID(st) == CFNumberGetTypeID()) {
    int v = 0;
    CFNumberGetValue((CFNumberRef)st, kCFNumberIntType, &v);
    enabled = v ? 1 : 0;
  }
  printf("  id=%-46s name=%-24s enabled=%s\n",
         id ? CFStringGetCStringPtr(id, kCFStringEncodingUTF8) : "(null)",
         name ? CFStringGetCStringPtr(name, kCFStringEncodingUTF8) : "(null)",
         enabled < 0 ? "?" : (enabled ? "YES" : "no"));
}

int main(int argc, char** argv) {
  // argv[1] 可选：按 id 子串选择要激活的输入源，留空则选 Squirrel 简体
  const char* want = (argc > 1 && argv[1][0]) ? argv[1] : NULL;

  CFArrayRef list = TISCreateInputSourceList(NULL, true);
  CFIndex n = CFArrayGetCount(list);

  printf("== 相关输入源 ==\n");
  TISInputSourceRef target = NULL;
  TISInputSourceRef fallback = NULL;  // 首个子串命中
  for (CFIndex i = 0; i < n; i++) {
    TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
    CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
    if (!id) continue;
    char buf[128] = {0};
    if (!CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8)) continue;
    if (want) {
      // 精确匹配优先；否则取首个子串命中。
      // 不能让最后一个命中者胜出：`ABC` 会同时匹配
      // com.apple.keylayout.ABC 与 com.apple.inputmethod.SCIM.ITABC，
      // 后者排在后面，于是「切到 ABC」实际切到了系统拼音。
      if (strcmp(buf, want) == 0) { dumpProps(s); target = s; break; }
      if (strstr(buf, want)) {
        dumpProps(s);
        if (!fallback) fallback = s;
      }
    } else if (strstr(buf, "Squirrel") || strstr(buf, "squirrel")) {
      dumpProps(s);
      if (strstr(buf, ".Hans")) target = s;  // 简体字版本
    }
  }
  if (want && !target) target = fallback;

  if (!target) {
    printf("\n未找到匹配的输入源（want=%s），无法继续。\n", want ? want : "(null)");
    return 1;
  }

  printf("\n== 执行启用 ==\n");
  OSStatus st = TISEnableInputSource(target);
  printf("  TISEnableInputSource -> %d (%s)\n", (int)st, st == noErr ? "成功" : "失败");

  printf("\n== 执行选中 ==\n");
  st = TISSelectInputSource(target);
  printf("  TISSelectInputSource -> %d (%s)\n", (int)st, st == noErr ? "成功" : "失败");

  printf("\n== 结果复核 ==\n");
  TISInputSourceRef cur = TISCopyCurrentKeyboardInputSource();
  if (cur) {
    CFStringRef id = (CFStringRef)TISGetInputSourceProperty(cur, kTISPropertyInputSourceID);
    char buf[128] = {0};
    if (id) CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8);
    printf("  当前输入源: %s\n", buf);
    CFRelease(cur);
  }
  dumpProps(target);
  return st == noErr ? 0 : 2;
}
