// click.c — 在指定屏幕坐标合成一次鼠标左键点击（CGEventPost, HID tap）。
// 用于真机复现菜单栏交互（AppleScript 的 AXPress 对状态栏按钮可能无效）。
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: %s x y [dwell_ms]\n", argv[0]); return 2; }
  CGPoint p = { atof(argv[1]), atof(argv[2]) };
  int dwell = argc > 3 ? atoi(argv[3]) : 120;
  CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, move); CFRelease(move);
  usleep(150 * 1000);
  CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, down); CFRelease(down);
  usleep(dwell * 1000);
  CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, up); CFRelease(up);
  printf("clicked %.0f,%.0f\n", p.x, p.y);
  return 0;
}
