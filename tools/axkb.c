// axkb.c — 打开/关闭系统"辅助功能键盘"（Accessibility Keyboard）。
//
// 为什么用它做真机验证：AppleScript/click 的 CGEvent 注入合成事件没有 HID
// 出身，IMKServer 会直接放行给前台控件，librime 收不到，所以永远验不出中文。
// 辅助功能键盘是系统自己在 AccessibilityKeyboard 进程里合成并经 HID 通道
// 投递的事件，带真实 provenance，会正常经过输入法链。
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

int main(int argc, char **argv) {
  int on = (argc > 1 && argv[1][0] == '1');
  // AccessibilityKeyboard 的 on/off 开关就是"辅助功能键盘"偏好项。
  // 官方推荐用 UIElementSetEnabled 切换（即等价于系统设置里那个开关）。
  UIElementSetEnabled((Boolean)on);
  printf("辅助功能键盘 = %s\n", on ? "已打开" : "已关闭");
  return 0;
}
