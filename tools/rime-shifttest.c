// 左 Shift 中英切换的端到端验证：用真实 librime + 用户真实配置，
// 模拟 Squirrel 实际发给引擎的事件序列。
//
// ⚠️ 不要在 app 包的 SharedSupport 目录下运行：librime 会把部署产物
//    （build/、installation.yaml、user.yaml）写进进程工作目录，污染 app 包。
//    用 argv[1] 指定 app 的 Contents 目录，在 /tmp 等无关目录下运行。
//
// 事件构造依据 SquirrelApplicationDelegate / SquirrelInputController：
//   - MacOSKeyCodes: kVK_Shift -> XK_Shift_L (56)
//   - osxModifiersToRime: shift 修饰键置 kShiftMask (1)
//   - .flagsChanged 分支：按下 processKey(XK_Shift_L, kShiftMask)
//                        抬起 processKey(XK_Shift_L, kShiftMask|kReleaseMask)
// librime 侧：AsciiComposer 在 500ms 内的修饰键单击，于抬起时调用
//   ToggleAsciiModeWithKey -> commit_code -> new_mode = !old_mode
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <rime_api_stdbool.h>
#include <rime_api.h>

// 自动探测安装位置：优先用户目录，其次系统目录；也可用 argv[1] 覆盖。
static char g_app[1024];
static const char* appDir(const char* override) {
  if (override && *override) { snprintf(g_app, sizeof g_app, "%s", override); return g_app; }
  const char* candidates[] = {
    "/Users/huangxt/Library/Input Methods/Squirrel.app/Contents",
    "/Library/Input Methods/Squirrel.app/Contents" };
  for (unsigned i = 0; i < sizeof candidates / sizeof candidates[0]; i++) {
    char probe[1100];
    snprintf(probe, sizeof probe, "%s/SharedSupport/default.yaml", candidates[i]);
    FILE* f = fopen(probe, "r");
    if (f) { fclose(f); snprintf(g_app, sizeof g_app, "%s", candidates[i]); return g_app; }
  }
  snprintf(g_app, sizeof g_app, "%s", candidates[0]);
  return g_app;
}
#define XK_Shift_L 0xffe1
#define XK_Escape 9
#define kShiftMask (1 << 0)
#define kReleaseMask (1 << 30)

static RimeApi_stdbool *api;
static RimeSessionId s;
static int fails = 0;

static void show(const char *stage) {
  RIME_STRUCT(RimeContext_stdbool, ctx);
  api->get_context(s, &ctx);
  printf("  %-26s preedit=%-12s ascii_mode=%-5s 候选数=%d",
         stage, ctx.composition.preedit ? ctx.composition.preedit : "(空)",
         api->get_option(s, "ascii_mode") ? "true" : "false",
         ctx.menu.num_candidates);
  if (ctx.menu.num_candidates > 0)
    printf("  首选=%s", ctx.menu.candidates[0].text);
  printf("\n");
  api->free_context(&ctx);
}

static void typeStr(const char *p) {
  for (; *p; p++) api->process_key(s, (int)(unsigned char)*p, 0);
}

// 默认方案以部署产物为准：build/default.yaml 的 schema_list 首位。
// 不能用会话当前方案断言——Rime 会恢复上次手选的方案，属正常行为。
static void defaultSchema(const char *userdir, char *out, size_t n) {
  out[0] = 0;
  char path[1200];
  snprintf(path, sizeof path, "%s/build/default.yaml", userdir);
  FILE *f = fopen(path, "r");
  if (!f) return;
  char line[512];
  int inList = 0;
  while (fgets(line, sizeof line, f)) {
    if (!inList) {
      if (strncmp(line, "schema_list:", 12) == 0) inList = 1;
      continue;
    }
    const char *p = strstr(line, "schema:");
    if (!p) break;  // 列表结束
    p += 7;
    while (*p == ' ') p++;
    const char *e = p;
    while (*e && *e != '\n' && *e != ' ' && *e != '"') e++;
    snprintf(out, n, "%.*s", (int)(e - p), p);
    break;  // 只取首位
  }
  fclose(f);
}

static void tapLeftShift(void) {
  api->process_key(s, XK_Shift_L, kShiftMask);
  usleep(120 * 1000);
  api->process_key(s, XK_Shift_L, kShiftMask | kReleaseMask);
  usleep(120 * 1000);
}

static void check(const char *what, int ok) {
  printf("  [%s] %s\n", ok ? "\033[32mPASS\033[0m" : "\033[31mFAIL\033[0m", what);
  if (!ok) fails = 1;
}

int main(int argc, char** argv) {
  api = rime_get_api_stdbool();
  if (!api) { printf("rime_get_api_stdbool() = NULL\n"); return 1; }

  RIME_STRUCT(RimeTraits, traits);
  const char* app = appDir(argc > 1 ? argv[1] : NULL);
  char shared[1200], userdir[1200];
  snprintf(shared, sizeof shared, "%s/SharedSupport", app);
  const char* home = getenv("HOME");
  snprintf(userdir, sizeof userdir, "%s/Library/Rime", home ? home : "/Users/huangxt");
  printf("  使用 shared_data_dir: %s\n  使用 user_data_dir  : %s\n", shared, userdir);
  traits.shared_data_dir = shared;
  traits.user_data_dir = userdir;
  traits.app_name = "rime.squirrel-shifttest";
  traits.distribution_name = "Squirrel shift test";
  traits.distribution_code_name = "Squirrel";
  traits.distribution_version = "1.1.2";
  api->setup(&traits);
  api->initialize(NULL);
  // 故意不跑 maintenance：直接用已编译好的 build/，避免改动配置

  printf("\n=== 会话初始状态 ===\n");
  char defschema[64] = {0};
  defaultSchema(userdir, defschema, sizeof defschema);
  check("部署配置默认方案是 wubi_pinyin（五笔·拼音混输）",
        strcmp(defschema, "wubi_pinyin") == 0);

  s = api->create_session();
  char schema[64] = {0};
  api->get_current_schema(s, schema, sizeof schema);
  printf("  会话当前方案: %s", schema);
  if (strcmp(schema, "wubi_pinyin") != 0) {
    api->select_schema(s, "wubi_pinyin");
    printf("（恢复为默认 wubi_pinyin）");
  }
  printf("\n");
  check("初始为中文态 ascii_mode=false", api->get_option(s, "ascii_mode") == False);

  printf("\n=== 1. 中文态打拼音 ===\n");
  typeStr("nihao");
  show("敲完 nihao");
  RIME_STRUCT(RimeContext_stdbool, c1);
  api->get_context(s, &c1);
  int has_cand = c1.menu.num_candidates > 0;
  int first_is_nihao =
      has_cand && strcmp(c1.menu.candidates[0].text, "你好") == 0;
  api->free_context(&c1);
  check("nihao 出现候选", has_cand);
  check("首选候选是「你好」", first_is_nihao);

  api->process_key(s, 0x20, 0);  // 空格上屏
  RIME_STRUCT(RimeCommit, cm1);
  api->get_commit(s, &cm1);
  printf("  上屏结果: [%s]\n", cm1.text ? cm1.text : "(无)");
  check("拼音上屏为「你好」", cm1.text && strcmp(cm1.text, "你好") == 0);
  api->free_commit(&cm1);

  printf("\n=== 1b. 中文态直接敲五笔码（混输） ===\n");
  {
    const char *codes[] = { "wq", "vb" };
    const char *want[] = { "你", "好" };
    for (unsigned i = 0; i < sizeof codes / sizeof codes[0]; i++) {
      typeStr(codes[i]);
      show(codes[i]);
      api->process_key(s, 0x20, 0);
      RIME_STRUCT(RimeCommit, cmw);
      api->get_commit(s, &cmw);
      printf("  上屏结果: [%s]\n", cmw.text ? cmw.text : "(无)");
      char msg[64];
      snprintf(msg, sizeof msg, "五笔码 %s 上屏为「%s」", codes[i], want[i]);
      check(msg, cmw.text && strcmp(cmw.text, want[i]) == 0);
      api->free_commit(&cmw);
    }
  }

  printf("\n=== 1c. 英文单词应出现在候选里（中英混选优化）===\n");
  {
    typeStr("hello");
    show("敲完 hello");
    // 英文候选 initial_quality 为负，排在五笔/拼音候选之后，可能不在首页：
    // 逐页查找（'=' 为 paging_with_minus_equal 的下一页键），找到即停。
    int found = 0;
    for (int page = 0; page < 60; page++) {
      RIME_STRUCT(RimeContext_stdbool, c);
      api->get_context(s, &c);
      for (int i = 0; i < c.menu.num_candidates; i++) {
        if (strcmp(c.menu.candidates[i].text, "hello") == 0) { found = 1; break; }
      }
      Bool last = c.menu.is_last_page;
      api->free_context(&c);
      if (found || last) break;
      if (!api->process_key(s, '=', 0)) break;  // 翻页键被拒说明没有更多页
    }
    check("英文单词 hello 出现在候选中", found);
    if (found) {
      int idx = -1;
      RIME_STRUCT(RimeContext_stdbool, c2);
      api->get_context(s, &c2);
      for (int i = 0; i < c2.menu.num_candidates; i++) {
        if (strcmp(c2.menu.candidates[i].text, "hello") == 0) { idx = i; break; }
      }
      api->free_context(&c2);
      if (idx >= 0) {
        api->process_key(s, '1' + idx, 0);  // 数字键选中该候选
        RIME_STRUCT(RimeCommit, cmh);
        api->get_commit(s, &cmh);
        printf("  上屏结果: [%s]\n", cmh.text ? cmh.text : "(无)");
        check("选中英文候选后上屏为「hello」",
              cmh.text && strcmp(cmh.text, "hello") == 0);
        api->free_commit(&cmh);
      }
    } else {
      api->process_key(s, XK_Escape, 0);  // 清掉编码，不影响后续断言
    }
  }

  printf("\n=== 2. 轻点左 Shift → 应切到英文态 ===\n");
  tapLeftShift();
  show("轻点左 Shift 后");
  check("ascii_mode 变为 true（英文态）", api->get_option(s, "ascii_mode") == True);

  printf("\n=== 3. 英文态按键应直通客户端（不经过 rime 转换）===\n");
  /* librime 1.17 AsciiComposer：ascii_mode 且非输入中时返回 kRejected，
     事件被放行给客户端直接插入，即纯英文直通。断言 process_key 返回 false。 */
  {
    int consumed = 0;
    for (const char *p = "abc"; *p; p++)
      if (api->process_key(s, (int)(unsigned char)*p, 0)) consumed++;
    printf("  abc 中被 rime 拦截的按键数: %d / 3\n", consumed);
    check("英文态下 abc 不被 rime 转换（直通客户端）", consumed == 0);
  }

  printf("\n=== 4. 再轻点左 Shift → 应切回中文态 ===\n");
  tapLeftShift();
  show("再次轻点左 Shift");
  check("ascii_mode 变回 false（中文态）", api->get_option(s, "ascii_mode") == False);

  printf("\n=== 5. 中文态恢复后再打一次 ===\n");
  typeStr("ceshi");
  show("敲完 ceshi");
  api->process_key(s, 0x20, 0);
  RIME_STRUCT(RimeCommit, cm3);
  api->get_commit(s, &cm3);
  printf("  上屏结果: [%s]\n", cm3.text ? cm3.text : "(无)");
  check("恢复中文态后能打出「测试」",
        cm3.text && strcmp(cm3.text, "测试") == 0);
  api->free_commit(&cm3);

  printf("\n=== 6. 按住左 Shift 打大写字母不应误切换 ===\n");
  tapLeftShift();  // 切到英文态
  tapLeftShift();  // 切回中文态
  api->process_key(s, XK_Shift_L, kShiftMask);          // 按下 Shift
  api->process_key(s, 'A', kShiftMask);                 // Shift+A
  api->process_key(s, XK_Shift_L, kShiftMask | kReleaseMask);  // 抬起 Shift
  show("Shift+A 之后");
  check("打大写字母后仍为中文态", api->get_option(s, "ascii_mode") == False);
  api->process_key(s, XK_Escape, 0);

  api->destroy_session(s);
  api->finalize();

  printf("\n%s\n", fails ? "\033[31m存在失败项\033[0m" : "\033[32m全部通过\033[0m");
  return fails;
}
