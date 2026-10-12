// tis-icon.c — 报告 TIS 为某个输入源解析出的菜单栏图标文件及其几何。
//
// 为什么需要它：菜单栏图标的最终形态由 TextInputMenuAgent 经 TIS 解析，
// 不看 Info.plist 里的 PNG 就无法区分「资源本身错」与「TIS 解析/缓存错」。
// kTISPropertyIconImageURL 直接给出 TIS 当前持有的图标文件 URL，
// 打印它的可达性与实际几何即可定位「两个图标高、上方空白」的来源。
//
// 构建（本机 clang 是 xcrun shim，需显式指定 SDK）：
//   SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
//   /Library/Developer/CommandLineTools/usr/bin/clang -isysroot "$SDK" \
//     -mmacosx-version-min=14.0 -o tis-icon tis-icon.c \
//     -framework Carbon -framework CoreFoundation -framework CoreGraphics \
//     -framework ImageIO -Wno-deprecated-declarations
//
// 用法： ./tis-icon                 （当前输入源）
//        ./tis-icon im.rime.inputmethod.Squirrel.Hans
//        TIS_ICON_OUT=/tmp/o.bmp ./tis-icon
#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dirent.h>
#include <unistd.h>

// TIS 给出的 icon_url 常是 bundle 相对路径（形如 Contents/Resources/x.png），
// 当绝对路径读必然失败——那只是探测端的解析缺陷，不代表 TIS 解析失败。
// 按候选安装根目录逐个拼出真实路径，取第一个存在的。
static int resolveIconPath(CFURLRef url, char *out, size_t outsz) {
  CFStringRef p = CFURLCopyPath(url);
  if (!p) return 0;
  // CFURLCopyPath 会给 "Input Methods" 里的空格编成 %20，而 readdir/open
  // 需要的是原始字节；用 CFURLCreateFromFileSystemRepresentation 的逆过程
  // CFStringGetCString 拿到的仍是编码串，所以这里手工做一次百分号解码。
  char enc[1024] = {0};
  if (!CFStringGetCString(p, enc, sizeof enc, kCFStringEncodingUTF8)) { CFRelease(p); return 0; }
  CFRelease(p);

  char path[1024];
  size_t o = 0;
  for (size_t i = 0; enc[i] && o + 1 < sizeof path; i++) {
    if (enc[i] == '%' && enc[i + 1] && enc[i + 2]) {
      char hex[3] = {enc[i + 1], enc[i + 2], 0};
      path[o++] = (char)strtol(hex, NULL, 16);
      i += 2;
    } else {
      path[o++] = enc[i];
    }
  }
  path[o] = 0;

  if (path[0] == '/') { snprintf(out, outsz, "%s", path); return 1; }

  const char *env = getenv("SQUIRREL_APP");
  const char *roots[] = {env ? env : "/Library/Input Methods", "/Library/Input Methods"};
  char full[2048];
  for (size_t r = 0; r < 1; r++) {
    DIR *d = opendir(roots[r]);
    if (!d) continue;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
      if (e->d_name[0] == '.') continue;
      snprintf(full, sizeof full, "%s/%s/%s", roots[r], e->d_name, path);
      CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)full,
                                                           (CFIndex)strlen(full), false);
      if (u && CFURLResourceIsReachable(u, NULL)) {
        printf("  resolved_rel=%s\n", full);
        closedir(d);
        CFRelease(u);
        snprintf(out, outsz, "%s", full);
        return 1;
      }
      if (u) CFRelease(u);
    }
    closedir(d);
  }
  return 0;
}

// 打印 alpha 包围盒：内容是否只落在画布下半部（= 用户看到的错位形态）
// 入参是已确认存在的绝对路径，避免再经 CFURL 取路径（会重新百分号编码）。
static void reportGeometry(const char *path) {
  printf("  reading=%s\n", path);
  if (access(path, R_OK) != 0) {
    printf("  image=UNREADABLE (路径不可读)\n");
    return;
  }
  CFURLRef src = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path,
                                                          (CFIndex)strlen(path), false);
  CGImageSourceRef is = CGImageSourceCreateWithURL(src, NULL);
  if (!is) {
    printf("  image=UNREADABLE (TIS 缓存的路径已失效 → 菜单栏画不出图标)\n");
    CFRelease(src);
    return;
  }
  size_t W = 0, H = 0;
  CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(is, 0, NULL);
  if (props) {
    CFNumberRef w = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
    CFNumberRef h = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
    if (w) CFNumberGetValue(w, kCFNumberIntType, &W);
    if (h) CFNumberGetValue(h, kCFNumberIntType, &H);
    CFRelease(props);
  }
  printf("  canvas=%zux%zu\n", W, H);

  CGImageRef img = CGImageSourceCreateImageAtIndex(is, 0, NULL);
  if (img) {
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(img));
    const UInt8 *px = (const UInt8 *)CFDataGetBytePtr(data);
    size_t stride = CGImageGetBytesPerRow(img);
    size_t ncomp = CGImageGetBitsPerPixel(img) / 8;
    long minx = (long)W, miny = (long)H, maxx = -1, maxy = -1;
    for (size_t y = 0; y < H; y++) {
      for (size_t x = 0; x < W; x++) {
        const UInt8 *q = px + y * stride + x * ncomp;
        unsigned a = (ncomp >= 4) ? q[ncomp - 1] : 255;
        if (a > 8) {
          if ((long)x < minx) minx = (long)x;
          if ((long)x > maxx) maxx = (long)x;
          if ((long)y < miny) miny = (long)y;
          if ((long)y > maxy) maxy = (long)y;
        }
      }
    }
    if (maxx < 0) {
      printf("  bbox=EMPTY (fully transparent)\n");
    } else {
      printf("  bbox=%ld,%ld..%ld,%ld ink=%ldx%ld\n",
             minx, miny, maxx, maxy, maxx - minx + 1, maxy - miny + 1);
      printf("  clear_rows_top=%ld clear_rows_bottom=%ld\n", miny, (long)H - 1 - maxy);
      // 症状判定：内容高度远小于画布，且顶部大片透明 → 视觉上「向下错位一行」
      if (miny > 0 && (long)H - 1 - maxy > 0)
        printf("  VERDICT=padded (上下均有透明边 → 菜单栏里会显得偏小/漂移)\n");
      else
        printf("  VERDICT=full-bleed (内容铺满画布，渲染不应出现错位)\n");
    }
    CFRelease(data);
    CGImageRelease(img);
  }
  CFRelease(is);
  CFRelease(src);
}

int main(int argc, char **argv) {
  TISInputSourceRef src = NULL;
  if (argc > 1) {
    CFStringRef want = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    CFArrayRef all = TISCreateInputSourceList(NULL, true);
    if (all) {
      for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
        TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(all, i);
        CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
        if (id && CFStringCompare(id, want, 0) == kCFCompareEqualTo) { src = s; break; }
      }
      CFRelease(all);
    }
    CFRelease(want);
    if (!src) { printf("input source not found: %s\n", argv[1]); return 1; }
  } else {
    src = TISCopyCurrentKeyboardInputSource();
    if (!src) { printf("no current input source\n"); return 1; }
  }

  CFStringRef id = (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
  CFStringRef name = (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyLocalizedName);
  char idb[200] = {0}, nameb[128] = {0};
  if (id) CFStringGetCString(id, idb, sizeof idb, kCFStringEncodingUTF8);
  if (name) CFStringGetCString(name, nameb, sizeof nameb, kCFStringEncodingUTF8);
  printf("%s %s\n", idb, nameb);

  CFURLRef iurl = (CFURLRef)TISGetInputSourceProperty(src, kTISPropertyIconImageURL);
  if (!iurl) {
    printf("  icon_url=NULL (TIS 没有该输入源的图标 → 菜单栏会退化/空白)\n");
    CFRelease(src);
    return 2;
  }
  char real[2048];
  if (!resolveIconPath(iurl, real, sizeof real)) {
    printf("  resolve=FAILED (未在已安装包内找到该图标文件)\n");
    CFRelease(src);
    return 3;
  }
  reportGeometry(real);

  // 顺带打印 tsInputMode*IconFileKey 在系统侧解析到的候选路径
  printf("  -- Info.plist 声明 --\n");
  CFTypeRef key = (CFTypeRef)kTISPropertyBundleID;
  CFStringRef bid = (CFStringRef)TISGetInputSourceProperty(src, key);
  char bidb[200] = {0};
  if (bid) CFStringGetCString(bid, bidb, sizeof bidb, kCFStringEncodingUTF8);
  printf("  bundle_id=%s\n", bidb);

  CFRelease(src);
  return 0;
}
