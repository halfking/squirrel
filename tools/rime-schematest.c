// rime-schematest.c — 方案行为诊断：指定方案与按键序列，打印候选与上屏。
//
// ⚠️ 不要在 app 包的 SharedSupport 目录下运行：librime 会把部署产物写进
//    进程工作目录，污染 app 包。用 argv[1] 指定 app 的 Contents 目录即可。
//
// 用法： rime-schematest [app_Contents_dir] <schema_id> <键序列>...
//   键序列中 `_` 表示敲一下空格（上屏首选），其余字符逐键送引擎。
//   例： rime-schematest "" wubi_pinyin nihao _ wq _ vb _
// 每个 `_` 前打印一次候选快照；`_` 后打印上屏文本。
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <rime_api_stdbool.h>
#include <rime_api.h>

static RimeApi_stdbool *api;
static RimeSessionId s;

static void appDir(char *out, size_t n, const char *override) {
  if (override && *override) { snprintf(out, n, "%s", override); return; }
  const char *home = getenv("HOME");
  const char *cands[2] = { "/Library/Input Methods/Squirrel.app/Contents", NULL };
  char user[1024];
  snprintf(user, sizeof user, "%s/Library/Input Methods/Squirrel.app/Contents",
           home ? home : "/Users/huangxt");
  cands[1] = user;
  for (int i = 0; i < 2; i++) {
    char probe[1100];
    snprintf(probe, sizeof probe, "%s/SharedSupport/default.yaml", cands[i]);
    FILE *f = fopen(probe, "r");
    if (f) { fclose(f); snprintf(out, n, "%s", cands[i]); return; }
  }
  snprintf(out, n, "%s", cands[0]);
}

static void dump(const char *stage) {
  RIME_STRUCT(RimeContext_stdbool, ctx);
  api->get_context(s, &ctx);
  printf("  %-14s preedit=%-10s ascii=%s 候选%d:",
         stage, ctx.composition.preedit ? ctx.composition.preedit : "(空)",
         api->get_option(s, "ascii_mode") ? "Y" : "n", ctx.menu.num_candidates);
  int n = ctx.menu.num_candidates > 5 ? 5 : ctx.menu.num_candidates;
  for (int i = 0; i < n; i++) printf(" %s", ctx.menu.candidates[i].text);
  printf("%s\n", ctx.menu.num_candidates > 5 ? " …" : "");
  api->free_context(&ctx);
}

static void tapSpace(void) {
  api->process_key(s, 0x20, 0);
  RIME_STRUCT(RimeCommit, cm);
  api->get_commit(s, &cm);
  printf("    └ 上屏: [%s]\n", cm.text ? cm.text : "(无)");
  api->free_commit(&cm);
}

int main(int argc, char **argv) {
  int argi = 1;
  char app[1024];
  appDir(app, sizeof app, argc > argi && strchr(argv[argi], '/') ? argv[argi] : NULL);
  if (argc > argi && strchr(argv[argi], '/')) argi++;
  if (argc - argi < 2) {
    fprintf(stderr, "用法: %s [app_dir] <schema> <键序列>... (_=空格)\n", argv[0]);
    return 2;
  }
  const char *schema = argv[argi++];

  api = rime_get_api_stdbool();
  RIME_STRUCT(RimeTraits, traits);
  char shared[1200], userdir[1200];
  const char *home = getenv("HOME");
  snprintf(shared, sizeof shared, "%s/SharedSupport", app);
  snprintf(userdir, sizeof userdir, "%s/Library/Rime", home ? home : "/Users/huangxt");
  printf("shared=%s\nuser=%s\n方案=%s\n", shared, userdir, schema);
  traits.shared_data_dir = shared;
  traits.user_data_dir = userdir;
  traits.app_name = "rime.squirrel-schematest";
  traits.distribution_name = "Squirrel schema test";
  traits.distribution_code_name = "Squirrel";
  traits.distribution_version = "1.1.2";
  api->setup(&traits);
  api->initialize(NULL);

  s = api->create_session();
  if (!api->select_schema(s, schema)) { printf("select_schema(%s) 失败\n", schema); return 1; }

  for (; argi < argc; argi++) {
    printf("== 输入 [%s] ==\n", argv[argi]);
    for (const char *p = argv[argi]; *p; p++) {
      if (*p == '_') { tapSpace(); continue; }
      api->process_key(s, (int)(unsigned char)*p, 0);
    }
    dump("结束态");
  }
  api->destroy_session(s);
  api->finalize();
  return 0;
}
