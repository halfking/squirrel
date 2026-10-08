// tis-register.c — 强制让 TIS 重新扫描指定 app 包并登记其输入源。
// 用法：tis-register /Library/Input\ Methods/Squirrel.app
//
// 为什么需要它：SquirrelInstaller.register() 只在"没有任何 Squirrel 模式已
// 注册"时才调 TISRegisterInputSource；原位替换 bundle 内容后版本变了、模式 id
// 没变，注册被跳过，TIS 仍持旧 bundle 的元数据——TISSelectInputSource 会以
// paramErr(-50) 拒绝选中。这里无条件重扫，配合 tis-select 使用。
#include <Carbon/Carbon.h>
#include <stdio.h>

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "用法: tis-register <app 路径>\n"); return 64; }
  CFStringRef path = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
  CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, true);
  if (!path || !url) { fprintf(stderr, "路径不合法\n"); return 64; }

  OSStatus e = TISRegisterInputSource(url);
  printf("TISRegisterInputSource(%s) -> %d (%s)\n", argv[1], (int)e,
         e == noErr ? "成功" : "失败");
  CFRelease(url);
  CFRelease(path);
  return e == noErr ? 0 : 2;
}
