// 对照实验：librime 对「抬起事件掩码」到底认哪一种？
//
// 背景 —— 之前的 rime-shifttest.c 在抬起时送 kShiftMask|kReleaseMask，
// 但真实 app（SquirrelInputController.swift:85）送的是：
//     rimeModifiers = osxModifiersToRime(modifiers)   // 抬起后已不含 .shift
//     buffer.insert((keycode, rimeModifiers | kReleaseMask), at: 0)
// 即 press   -> process_key(XK_Shift_L, kShiftMask)
//    release -> process_key(XK_Shift_L, kReleaseMask)      ← 没有 shift 位
//
// 两者不一致，必须实测 librime 1.17.0 到底认哪一种。
// 本程序把同一套断言跑两遍，逐一对照。
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <rime_api_stdbool.h>
#include <rime_api.h>

#define XK_Shift_L 0xffe1
#define XK_Escape 9
#define XK_BackSpace 0xFF08
#define kShiftMask (1 << 0)
#define kReleaseMask (1 << 30)

static char g_app[1024];
static const char* appDir(void) {
  // 环境变量优先：可指向暂存/试验用的 SharedSupport 父目录，
  // 这样验证补丁效果时不必改动已安装且已签名的 app 包。
  const char* env = getenv("SQUIRREL_APP_DIR");
  if (env && *env) { snprintf(g_app, sizeof g_app, "%s", env); return g_app; }
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

static RimeApi_stdbool* api;
static int fails = 0;

static void check(const char* what, int ok) {
  printf("    [%s] %s\n", ok ? "\033[32mPASS\033[0m" : "\033[31mFAIL\033[0m", what);
  if (!ok) fails = 1;
}

static RimeSessionId s;

static void tap(int releaseWithShift) {
  api->process_key(s, XK_Shift_L, kShiftMask);
  usleep(150 * 1000);
  api->process_key(s, XK_Shift_L,
                   kReleaseMask | (releaseWithShift ? kShiftMask : 0u));
  usleep(150 * 1000);
}

static void typeStr(const char* p) {
  for (; *p; p++) api->process_key(s, (int)(unsigned char)*p, 0);
}

static void dumpState(const char* tag) {
  RIME_STRUCT(RimeContext_stdbool, c);
  api->get_context(s, &c);
  printf("    <%s> ascii_mode=%s preedit=[%s] len=%d cursor=%d 候选数=%d\n", tag,
         api->get_option(s, "ascii_mode") ? "true" : "false",
         c.composition.preedit ? c.composition.preedit : "",
         c.composition.length, c.composition.cursor_pos, c.menu.num_candidates);
  api->free_context(&c);
}

// 跑完整套断言。mode: 0=app 真实行为(仅 kReleaseMask) 1=旧测试(kShiftMask|kReleaseMask)
static void runSuite(const char* title, int releaseWithShift) {
  printf("\n\033[1m=== 用例 %s ===\033[0m\n", title);
  printf("  抬起事件掩码: 0x%x %s\n", kReleaseMask | (releaseWithShift ? kShiftMask : 0),
         releaseWithShift ? "(kShiftMask|kReleaseMask — 旧测试假设)"
                          : "(仅 kReleaseMask — 真实 app 行为)");

  // 初始态
  api->process_key(s, XK_Escape, 0);
  usleep(80 * 1000);
  dumpState("用例开始前");
  while (api->get_option(s, "ascii_mode") == True) { tap(releaseWithShift); }
  check("初始归位为中文态", api->get_option(s, "ascii_mode") == False);

  // 1) 中文态能打出中文
  typeStr("nihao");
  dumpState("敲完 nihao");
  RIME_STRUCT(RimeContext_stdbool, c1);
  api->get_context(s, &c1);
  int has_cand = c1.menu.num_candidates > 0;
  int first_ok = has_cand && strcmp(c1.menu.candidates[0].text, "你好") == 0;
  api->free_context(&c1);
  check("nihao 出现候选且首选「你好」", has_cand && first_ok);
  api->process_key(s, 0x20, 0);
  RIME_STRUCT(RimeCommit, cm);
  api->get_commit(s, &cm);
  check("上屏为「你好」", cm.text && strcmp(cm.text, "你好") == 0);
  api->free_commit(&cm);

  // 2) 轻点左 Shift -> 英文态
  tap(releaseWithShift);
  int after_tap1 = api->get_option(s, "ascii_mode") == True;
  check("轻点左 Shift 后切到英文态", after_tap1);

  // 3) 英文态直通
  int consumed = 0;
  for (const char* p = "abc"; *p; p++)
    if (api->process_key(s, (int)(unsigned char)*p, 0)) consumed++;
  check("英文态 abc 直通客户端（0/3 被拦截）", consumed == 0);
  api->process_key(s, XK_Escape, 0);

  // 4) 再点 -> 中文态
  tap(releaseWithShift);
  check("再点左 Shift 切回中文态", api->get_option(s, "ascii_mode") == False);

  // 5) 恢复后能再打中文
  typeStr("ceshi");
  api->process_key(s, 0x20, 0);
  RIME_STRUCT(RimeCommit, cm2);
  api->get_commit(s, &cm2);
  check("恢复后能打出「测试」", cm2.text && strcmp(cm2.text, "测试") == 0);
  api->free_commit(&cm2);

  // 6) 按住 shift 打大写字母不误切
  tap(releaseWithShift);
  tap(releaseWithShift);
  api->process_key(s, XK_Shift_L, kShiftMask);
  usleep(60 * 1000);
  api->process_key(s, 'A', kShiftMask);
  usleep(60 * 1000);
  api->process_key(s, XK_Shift_L, kReleaseMask | (releaseWithShift ? kShiftMask : 0));
  usleep(120 * 1000);
  check("Shift+A 后仍为中文态", api->get_option(s, "ascii_mode") == False);

  // 7) Shift+A 泄漏的字母必须能被 Escape 清掉
  //    这是真实用户可见行为：按 Shift 打个大写字母后，候选区可能残留，
  //    若 Escape 清不掉，后续输入会被污染成 "Anihao" 之类。
  dumpState("Shift+A 之后");
  api->process_key(s, XK_Escape, 0);
  usleep(150 * 1000);
  {
    RIME_STRUCT(RimeContext_stdbool, ce);
    api->get_context(s, &ce);
    int leftover = ce.composition.length;
    api->free_context(&ce);
    // Escape 可能是「丢弃」，也可能是「原样提交」——两种都不该让字母留在候选区。
    // 先把可能产生的 commit 取出来，否则它会一直挂在那里。
    RIME_STRUCT(RimeCommit, cmt);
    api->get_commit(s, &cmt);
    const char* committed = cmt.text ? cmt.text : "(无)";
    printf("    <Escape 产生的 commit> [%s]\n", committed);
    if (cmt.text) api->free_commit(&cmt);
    check("Shift+A 之后按 Escape 不残留候选（清空或提交）", leftover == 0);
    if (leftover != 0) dumpState("Escape 之后(仍残留)");
  }

  // 8) 清场后必须能立刻正常打中文（防污染回归）
  typeStr("nihao");
  api->process_key(s, 0x20, 0);
  RIME_STRUCT(RimeCommit, cm3);
  api->get_commit(s, &cm3);
  check("清场后立刻能打出「你好」", cm3.text && strcmp(cm3.text, "你好") == 0);
  api->free_commit(&cm3);

  // 9) 对照组：Control+g 是 stock 配置里本来就有的 Escape 绑定
  //    （build/default.yaml: {accept: "Control+g", send: Escape, when: composing}）
  //    如果连它都清不掉，说明本测试根本没走到 key_binder 组件，
  //    那么上面第 7 项的失败就不能用来判定配置缺陷。
  {
    api->process_key(s, XK_Shift_L, kShiftMask);
    usleep(50 * 1000);
    api->process_key(s, 'A', kShiftMask);
    usleep(50 * 1000);
    api->process_key(s, XK_Shift_L, kReleaseMask | (releaseWithShift ? kShiftMask : 0));
    usleep(80 * 1000);
    api->process_key(s, 'g', 1 << 2);  // Control+g
    usleep(150 * 1000);
    RIME_STRUCT(RimeContext_stdbool, cg);
    api->get_context(s, &cg);
    int left = cg.composition.length;
    api->free_context(&cg);
    RIME_STRUCT(RimeCommit, cg2);
    api->get_commit(s, &cg2);
    printf("    <Control+g 之后> 残留=%d commit=[%s]\n", left, cg2.text ? cg2.text : "(无)");
    if (cg2.text) api->free_commit(&cg2);
    check("对照组 Control+g（stock 绑定）能清掉候选区", left == 0);
    api->process_key(s, XK_Escape, 0);
  }

  // 10) 逃生口：Backspace 能不能清掉卡住的字母
  //     这是给用户的实际对策——裸 Escape 不行，Backspace 行不行。
  {
    api->process_key(s, XK_Shift_L, kShiftMask);
    usleep(50 * 1000);
    api->process_key(s, 'A', kShiftMask);
    usleep(50 * 1000);
    api->process_key(s, XK_Shift_L, kReleaseMask | (releaseWithShift ? kShiftMask : 0));
    usleep(80 * 1000);
    api->process_key(s, XK_BackSpace, 0);
    usleep(150 * 1000);
    RIME_STRUCT(RimeContext_stdbool, cb);
    api->get_context(s, &cb);
    int left2 = cb.composition.length;
    api->free_context(&cb);
    check("Backspace 能清掉卡住的字母", left2 == 0);
    // 清完必须能正常继续打字
    typeStr("nihao");
    api->process_key(s, 0x20, 0);
    RIME_STRUCT(RimeCommit, cm4);
    api->get_commit(s, &cm4);
    check("Backspace 清场后能打出「你好」", cm4.text && strcmp(cm4.text, "你好") == 0);
    if (cm4.text) api->free_commit(&cm4);
    else { RIME_STRUCT(RimeCommit, t); api->get_commit(s, &t); if (t.text) api->free_commit(&t); }
  }
}

int main(int argc, char** argv) {
  api = rime_get_api_stdbool();
  if (!api) { printf("rime_get_api_stdbool() = NULL\n"); return 1; }

  RIME_STRUCT(RimeTraits, traits);
  const char* app = appDir();
  char shared[1200], userdir[1200];
  snprintf(shared, sizeof shared, "%s/SharedSupport", app);
  // SQUIRREL_USER_DIR 直接就是 Rime 用户目录本身（形如 ~/Library/Rime），
  // 不再拼接任何后缀——早期版本错误地追加了 "/Library/Rime"，
  // 导致隔离测试指向一个空目录，配置与码表全部没加载。
  const char* env_user = getenv("SQUIRREL_USER_DIR");
  snprintf(userdir, sizeof userdir, "%s",
           (env_user && *env_user) ? env_user : "/Users/huangxt/Library/Rime");
  printf("  shared_data_dir: %s\n  user_data_dir  : %s\n", shared, userdir);
  traits.shared_data_dir = shared;
  traits.user_data_dir = userdir;
  traits.app_name = "rime.squirrel-shifttest-variants";
  traits.distribution_name = "Squirrel shift variants";
  traits.distribution_code_name = "Squirrel";
  traits.distribution_version = "1.1.2";
  api->setup(&traits);
  api->initialize(NULL);

  // argv[1] == "deploy" 时先重新部署配置，让 default.custom.yaml 生效
  if (argc > 1 && strcmp(argv[1], "deploy") == 0) {
    printf("\n=== 正在重新部署 Rime 配置（可能需要几十秒）===\n");
    api->start_maintenance(True);
    api->join_maintenance_thread();
    printf("=== 部署完成 ===\n");
  }

  s = api->create_session();
  char schema[64] = {0};
  api->get_current_schema(s, schema, sizeof schema);
  printf("  当前方案: %s\n", schema);

  // 每个用例用全新会话，避免上一个用例残留的候选区污染下一个
  runSuite("A：真实 app 行为（抬起仅 kReleaseMask）", 0);
  api->destroy_session(s);
  s = api->create_session();
  runSuite("B：旧测试假设（抬起 kShiftMask|kReleaseMask）", 1);

  api->destroy_session(s);
  api->finalize();

  printf("\n%s\n", fails ? "\033[31m存在失败项\033[0m" : "\033[32m全部通过\033[0m");
  return fails;
}
