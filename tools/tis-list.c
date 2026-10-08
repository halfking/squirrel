// tis-list.c — 列出系统输入源：已启用的输入法 + 当前选中源。
// 供 tools/ime-healthcheck.sh 第 2 节消费（缺它该节整体跳过）。
// 输出格式约定（healthcheck 按标记行切片）：
//   == enabled input methods ==
//   == current ==
// 最后一行必须含当前输入源 id（healthcheck 取末行判断当前源）。
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

static void printSource(TISInputSourceRef s, const char *prefix) {
  CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
  CFStringRef name = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyLocalizedName);
  char idb[160] = {0}, nameb[128] = {0};
  if (id) CFStringGetCString(id, idb, sizeof idb, kCFStringEncodingUTF8);
  if (name) CFStringGetCString(name, nameb, sizeof nameb, kCFStringEncodingUTF8);
  printf("%s id=%-46s name=%s\n", prefix, idb, nameb);
}

int main(void) {
  printf("== enabled input methods ==\n");
  // 只列输入法类（排除键盘布局），与「系统设置 → 键盘 → 输入法」口径一致
  CFStringRef keys[] = { kTISPropertyInputSourceCategory };
  CFTypeRef vals[] = { kTISCategoryKeyboardInputSource };
  CFDictionaryRef filter = CFDictionaryCreate(NULL, (const void**)keys,
                                              (const void**)vals, 1,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
  CFArrayRef list = TISCreateInputSourceList(filter, false);
  if (list) {
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++)
      printSource((TISInputSourceRef)CFArrayGetValueAtIndex(list, i), " ");
    CFRelease(list);
  }
  printf("== current ==\n");
  TISInputSourceRef cur = TISCopyCurrentKeyboardInputSource();
  if (cur) {
    printSource(cur, " ");
    CFRelease(cur);
  }
  return 0;
}
