// keypress.c — 合成一次全局快捷键（CGEventPost 到 HID tap），用于调出
// 系统面板（如 Control+Space 输入源切换）。osascript 的 System Events
// key code 对部分系统面板无效；直接 CGEventPost(kCGHIDEventTap) 有效。
// 用法： keypress < keycode> [modifier...]   修饰键名：ctrl alt cmd shift
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: %s <keycode> [ctrl|alt|cmd|shift]\n", argv[0]); return 2; }
  CGKeyCode key = (CGKeyCode)atoi(argv[1]);
  CGEventFlags flags = 0;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "ctrl")) flags |= kCGEventFlagMaskControl;
    else if (!strcmp(argv[i], "alt")) flags |= kCGEventFlagMaskAlternate;
    else if (!strcmp(argv[i], "cmd")) flags |= kCGEventFlagMaskCommand;
    else if (!strcmp(argv[i], "shift")) flags |= kCGEventFlagMaskShift;
  }
  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  CGEventRef down = CGEventCreateKeyboardEvent(src, key, true);
  if (flags) CGEventSetFlags(down, flags | CGEventGetFlags(down));
  CGEventPost(kCGHIDEventTap, down); CFRelease(down);
  usleep(60 * 1000);
  CGEventRef up = CGEventCreateKeyboardEvent(src, key, false);
  if (flags) CGEventSetFlags(up, flags | CGEventGetFlags(up));
  CGEventPost(kCGHIDEventTap, up); CFRelease(up);
  CFRelease(src);
  printf("key %d sent\n", key);
  return 0;
}
