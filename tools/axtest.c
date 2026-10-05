// axtest.c — 触发 macOS 辅助功能(Accessibility)授权提示，并报告当前授权状态。
// 授权归属于「发起进程」：在 MiniMax Code 里运行后，需在
// 系统设置 → 隐私与安全性 → 辅助功能 中打开 "MiniMax Code"。
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

int main(void) {
  CFStringRef key = CFSTR("AXTrustedCheckOptionPrompt");
  const void *vals[] = {kCFBooleanTrue};
  CFDictionaryRef opts =
      CFDictionaryCreate(NULL, (const void **)&key, vals, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  Boolean trusted = AXIsProcessTrustedWithOptions(opts);
  if (opts) CFRelease(opts);

  if (trusted) {
    printf("TRUSTED\n");
    return 0;
  }
  printf("NOT_TRUSTED\n");
  fprintf(stderr,
          "尚未授权。请在「系统设置 → 隐私与安全性 → 辅助功能」中打开 "
          "「MiniMax Code」，然后重新运行本程序。\n");
  return 2;
}
