// tis-select.c — 按输入源 id 选中并复核当前源。
// 用法：tis-select <TISInputSourceID>
// 供对照实验使用：把系统切到指定输入法，再由外部投递按键。
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

static CFStringRef copySourceByID(CFStringRef want, TISInputSourceRef *out) {
  // 先在"已启用"列表里找（includeAll=false）：对 includeAll=true 拿到的
  // 未激活实例调 TISSelectInputSource 会报 paramErr(-50)。
  CFStringRef filterKeys[] = { kTISPropertyInputSourceID };
  CFTypeRef filterValues[] = { want };
  CFDictionaryRef filter = CFDictionaryCreate(NULL, (const void**)filterKeys,
                                              (const void**)filterValues, 1,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
  CFArrayRef list = TISCreateInputSourceList(filter, false);
  if (!list || CFArrayGetCount(list) == 0) {
    if (list) CFRelease(list);
    list = TISCreateInputSourceList(NULL, true);  // 回退：全量列表
  }
  if (!list) return NULL;
  CFIndex n = CFArrayGetCount(list);
  CFStringRef found = NULL;
  for (CFIndex i = 0; i < n; i++) {
    TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
    CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
    if (!id) continue;
    if (CFStringCompare(id, want, kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
      found = CFStringCreateCopy(NULL, id);
      if (out) *out = (TISInputSourceRef)CFRetain(s);
      break;
    }
  }
  CFRelease(list);
  return found;
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "用法: tis-select <TISInputSourceID>\n"); return 64; }
  CFStringRef want = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
  if (!want) { fprintf(stderr, "参数不是合法 UTF-8\n"); return 64; }

  TISInputSourceRef src = NULL;
  CFStringRef id = copySourceByID(want, &src);
  if (!id) { printf("未找到输入源: %s\n", argv[1]); CFRelease(want); return 1; }

  OSStatus e = TISEnableInputSource(src);
  OSStatus s = TISSelectInputSource(src);
  printf("select %s -> enable=%d select=%d\n", argv[1], (int)e, (int)s);

  TISInputSourceRef cur = TISCopyCurrentKeyboardInputSource();
  if (cur) {
    CFStringRef cid = (CFStringRef)TISGetInputSourceProperty(cur, kTISPropertyInputSourceID);
    char b[128] = {0};
    if (cid) CFStringGetCString(cid, b, sizeof b, kCFStringEncodingUTF8);
    printf("当前源: %s\n", b);
    CFRelease(cur);
  }
  return s == noErr ? 0 : 2;
}
