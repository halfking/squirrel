/*
 *  squirrel_setup.c — Squirrel 鼠鬚管安装程序 / Squirrel Setup (Linux, GTK 3)
 *
 *  A native GTK wizard that installs the Rime engine (fcitx5-rime / ibus-rime)
 *  and deploys this repository's shared user configuration, the same five steps
 *  as the macOS and Windows setup programs.
 *
 *  Built with:  zig cc -target x86_64-linux-gnu (or a native gcc toolchain)
 */

#include <gtk/gtk.h>
#include <glib.h>
#include <glib/gi18n.h>
#include <glib/gstdio.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "payload.h" /* default_custom_yaml, presets_json (generated at build time) */

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

typedef enum {
  STEP_PENDING = 0,
  STEP_RUNNING,
  STEP_DONE,
  STEP_SKIPPED,
  STEP_FAILED
} StepState;

static const char *step_glyph(StepState state) {
  switch (state) {
    case STEP_RUNNING: return "◐";
    case STEP_DONE:    return "✓";
    case STEP_SKIPPED: return "⊘";
    case STEP_FAILED:  return "✕";
    default:           return "○";
  }
}

static char *xstrdup(const char *s) { return s ? g_strdup(s) : NULL; }

static gboolean file_exists(const char *path) {
  return path && access(path, F_OK) == 0;
}

static char *path_join(const char *a, const char *b) { return g_build_filename(a, b, NULL); }

static const char *home_dir(void) {
  const char *home = g_getenv("HOME");
  return (home && *home) ? home : g_get_home_dir();
}

static gboolean dir_exists(const char *path) {
  GStatBuf st;
  return path && g_stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static char *read_file(const char *path, gsize *length_out) {
  gchar *contents = NULL;
  gsize length = 0;
  if (!g_file_get_contents(path, &contents, &length, NULL)) return NULL;
  if (length_out) *length_out = length;
  return contents;
}

static gboolean write_file(const char *path, const char *contents, gsize length) {
  char *dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0755);
  g_free(dir);
  return g_file_set_contents(path, contents, length, NULL);
}

/* Run `command` through /bin/sh and capture stdout+stderr.
 * popen() is used on purpose: these commands rely on shell features
 * (redirection, &&, ||, command substitution, background jobs). */
static char *run_capture(const char *command, int *exit_code) {
  int code = -1;
  FILE *pipe = popen(command, "r");
  if (!pipe) {
    if (exit_code) *exit_code = -1;
    return NULL;
  }
  GString *buffer = g_string_new(NULL);
  char chunk[4096];
  size_t n;
  while ((n = fread(chunk, 1, sizeof(chunk), pipe)) > 0)
    g_string_append_len(buffer, chunk, (gssize)n);
  int status = pclose(pipe);
  if (WIFEXITED(status)) code = WEXITSTATUS(status);
  if (exit_code) *exit_code = code;
  return g_string_free(buffer, FALSE);
}

/* Replace every occurrence of `find` in `*text` with `replacement`. */
static void str_replace(char **text, const char *find, const char *replacement) {
  if (!*text || !find || !*find) return;
  GString *out = g_string_new(NULL);
  const char *cursor = *text;
  size_t find_length = strlen(find);
  for (;;) {
    const char *hit = strstr(cursor, find);
    if (!hit) { g_string_append(out, cursor); break; }
    g_string_append_len(out, cursor, (gssize)(hit - cursor));
    g_string_append(out, replacement);
    cursor = hit + find_length;
  }
  g_free(*text);
  *text = g_string_free(out, FALSE);
}

static char *trim(char *text) {
  if (!text) return NULL;
  g_strstrip(text);
  return text;
}

/* ------------------------------------------------------------------ */
/* Platform detection                                                  */
/* ------------------------------------------------------------------ */

typedef struct {
  char *distro_id;      /* debian / arch / fedora …                       */
  char *distro_name;    /* human readable                                */
  char *package_manager;/* apt-get / dnf / pacman / zypper / apk          */
  char *fcitx5_rime_dir;/* ~/.local/share/fcitx5/rime                    */
  char *ibus_rime_dir;  /* ~/.config/ibus/rime                           */
  char *active_rime_dir;/* whichever exists, fcitx5 preferred            */
  const char *ime;      /* "fcitx5" | "ibus" | "none"                     */
} Platform;

static char *os_release_value(const char *key) {
  char *contents = read_file("/etc/os-release", NULL);
  if (!contents) return NULL;
  char *value = NULL;
  char **lines = g_strsplit(contents, "\n", -1);
  size_t key_length = strlen(key);
  for (char **line = lines; *line; ++line) {
    if (g_str_has_prefix(*line, key) && (*line)[key_length] == '=') {
      char *raw = *line + key_length + 1;
      g_strstrip(raw);
      size_t n = strlen(raw);
      if (n >= 2 && ((raw[0] == '"' && raw[n - 1] == '"') || (raw[0] == '\'' && raw[n - 1] == '\''))) {
        raw[n - 1] = '\0';
        raw++;
      }
      value = g_strdup(raw);
      break;
    }
  }
  g_strfreev(lines);
  g_free(contents);
  return value;
}

static const char *detect_package_manager(void) {
  static const char *managers[] = {"apt-get", "dnf", "pacman", "zypper", "apk", NULL};
  for (int i = 0; managers[i]; ++i) {
    char *probe = g_strdup_printf("command -v %s >/dev/null 2>&1", managers[i]);
    int code = 0;
    char *out = run_capture(probe, &code);
    g_free(out);
    g_free(probe);
    if (code == 0) return managers[i];
  }
  return NULL;
}

static const char *packages_for(const char *manager) {
  if (!manager) return "";
  if (g_str_equal(manager, "pacman"))
    return "fcitx5-rime rime-wubi rime-luna-pinyin";
  if (g_str_equal(manager, "apt-get"))
    return "fcitx5-rime fcitx5-rime-extra fcitx5-chinese-addons";
  if (g_str_equal(manager, "dnf"))
    return "fcitx5-rime";
  if (g_str_equal(manager, "zypper"))
    return "fcitx5-rime";
  if (g_str_equal(manager, "apk"))
    return "fcitx5-rime";
  return "";
}

static char *install_command(const char *manager, const char *packages) {
  if (!manager || !*packages) return NULL;
  if (g_str_equal(manager, "pacman"))
    return g_strdup_printf("pacman -S --needed --noconfirm %s", packages);
  if (g_str_equal(manager, "apt-get"))
    return g_strdup_printf("DEBIAN_FRONTEND=noninteractive apt-get install -y %s", packages);
  if (g_str_equal(manager, "dnf"))
    return g_strdup_printf("dnf install -y %s", packages);
  if (g_str_equal(manager, "zypper"))
    return g_strdup_printf("zypper --non-interactive install %s", packages);
  if (g_str_equal(manager, "apk"))
    return g_strdup_printf("apk add %s", packages);
  return NULL;
}

static void platform_init(Platform *platform) {
  memset(platform, 0, sizeof(*platform));
  platform->distro_id = os_release_value("ID");
  platform->distro_name = os_release_value("PRETTY_NAME");
  platform->package_manager = (char *)detect_package_manager();

  char *local = g_build_filename(home_dir(), ".local", "share", "fcitx5", "rime", NULL);
  char *ibus = g_build_filename(home_dir(), ".config", "ibus", "rime", NULL);
  platform->fcitx5_rime_dir = local;
  platform->ibus_rime_dir = ibus;

  if (dir_exists(local)) {
    platform->active_rime_dir = g_strdup(local);
    platform->ime = "fcitx5";
  } else if (dir_exists(ibus)) {
    platform->active_rime_dir = g_strdup(ibus);
    platform->ime = "ibus";
  } else {
    int code = 0;
    char *out = run_capture("command -v fcitx5-rime >/dev/null 2>&1 || command -v fcitx5 >/dev/null 2>&1", &code);
    g_free(out);
    if (code == 0) {
      platform->active_rime_dir = g_strdup(local);
      platform->ime = "fcitx5";
    } else {
      platform->active_rime_dir = g_strdup(local);
      platform->ime = "none";
    }
  }
}

static void platform_free(Platform *platform) {
  g_free(platform->distro_id);
  g_free(platform->distro_name);
  g_free(platform->package_manager);
  g_free(platform->fcitx5_rime_dir);
  g_free(platform->ibus_rime_dir);
  g_free(platform->active_rime_dir);
}

static gboolean fcitx5_rime_installed(void) {
  int code = 0;
  char *out = run_capture("command -v fcitx5 >/dev/null 2>&1", &code);
  g_free(out);
  if (code != 0) return FALSE;
  out = run_capture("test -d /usr/share/fcitx5/rime || test -d /usr/share/rime-data", &code);
  gboolean found = (code == 0);
  g_free(out);
  return found;
}

static gboolean ibus_rime_installed(void) {
  int code = 0;
  char *out = run_capture("command -v ibus >/dev/null 2>&1", &code);
  g_free(out);
  if (code != 0) return FALSE;
  out = run_capture("ls /usr/share/ibus/component/rime.xml >/dev/null 2>&1", &code);
  gboolean found = (code == 0);
  g_free(out);
  return found;
}

/* ------------------------------------------------------------------ */
/* UI model                                                            */
/* ------------------------------------------------------------------ */

typedef struct {
  const char *id;
  const char *title;
  const char *subtitle;
  GtkWidget *glyph;
  GtkWidget *detail;
  StepState state;
} Step;

typedef enum { EV_LOG, EV_STATE, EV_FINISH, EV_IDLE } EventType;

typedef struct {
  EventType type;
  int index;          /* step index for EV_STATE                     */
  StepState state;
  char *text;
  gboolean success;
} Event;

static struct {
  GtkWidget *window;
  GtkWidget *log_view;
  GtkWidget *progress;
  GtkWidget *status;
  GtkWidget *install_button;
  GtkWidget *detect_button;
  Step steps[6];
  int step_count;
  GQueue *events;    /* owned Event*                                */
  GMutex lock;
  gboolean running;
} app;

static void log_append(const char *text, const char *colour) {
  Event *event = g_new0(Event, 1);
  event->type = EV_LOG;
  event->text = g_strdup_printf("%s%s", colour, text);
  g_mutex_lock(&app.lock);
  g_queue_push_tail(app.events, event);
  g_mutex_unlock(&app.lock);
}

static void log_line(const char *fmt, ...) G_GNUC_PRINTF(1, 2);
static void log_line(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  char *message = g_strdup_vprintf(fmt, args);
  va_end(args);
  log_append(message, "");
  g_free(message);
}

static void log_ok(const char *fmt, ...) G_GNUC_PRINTF(1, 2);
static void log_ok(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  char *message = g_strdup_vprintf(fmt, args);
  va_end(args);
  log_append(message, "✓ ");
  g_free(message);
}

static void log_warn(const char *fmt, ...) G_GNUC_PRINTF(1, 2);
static void log_warn(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  char *message = g_strdup_vprintf(fmt, args);
  va_end(args);
  log_append(message, "! ");
  g_free(message);
}

static void log_error(const char *fmt, ...) G_GNUC_PRINTF(1, 2);
static void log_error(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  char *message = g_strdup_vprintf(fmt, args);
  va_end(args);
  log_append(message, "✕ ");
  g_free(message);
}

static void set_state(int index, StepState state, const char *detail) {
  Event *event = g_new0(Event, 1);
  event->type = EV_STATE;
  event->index = index;
  event->state = state;
  event->text = xstrdup(detail);
  g_mutex_lock(&app.lock);
  g_queue_push_tail(app.events, event);
  g_mutex_unlock(&app.lock);
}

static int step_index(const char *id) {
  for (int i = 0; i < app.step_count; ++i)
    if (g_str_equal(app.steps[i].id, id)) return i;
  return -1;
}

static void event_free(Event *event) {
  g_free(event->text);
  g_free(event);
}

static void apply_state(Event *event) {
  if (event->index < 0 || event->index >= app.step_count) return;
  Step *step = &app.steps[event->index];
  step->state = event->state;
  gtk_label_set_text(GTK_LABEL(step->glyph), step_glyph(event->state));
  const char *colour = "#000000";
  switch (event->state) {
    case STEP_RUNNING: colour = "#B26A00"; break;
    case STEP_DONE:    colour = "#1B7F3B"; break;
    case STEP_SKIPPED: colour = "#808080"; break;
    case STEP_FAILED:  colour = "#C0392B"; break;
    default: break;
  }
  GdkRGBA rgba;
  gdk_rgba_parse(&rgba, colour);
  gtk_widget_override_color(step->glyph, GTK_STATE_FLAG_NORMAL, &rgba);

  if (event->state == STEP_RUNNING)
    gtk_label_set_text(GTK_LABEL(step->detail), "进行中…");
  else
    gtk_label_set_text(GTK_LABEL(step->detail), event->text ? event->text : "");

  if (event->state == STEP_DONE || event->state == STEP_SKIPPED || event->state == STEP_FAILED)
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(app.progress), (double)(event->index + 1) / 6.0);
}

static gboolean drain_events(gpointer unused) {
  (void)unused;
  for (;;) {
    g_mutex_lock(&app.lock);
    Event *event = g_queue_pop_head(app.events);
    g_mutex_unlock(&app.lock);
    if (!event) break;

    switch (event->type) {
      case EV_LOG: {
        GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(app.log_view));
        GtkTextIter end;
        gtk_text_buffer_get_end_iter(buffer, &end);
        gtk_text_buffer_insert(buffer, &end, event->text, -1);
        gtk_text_buffer_get_end_iter(buffer, &end);
        gtk_text_buffer_insert(buffer, &end, "\n", -1);
        GtkTextMark *mark = gtk_text_buffer_create_mark(buffer, NULL, &end, FALSE);
        gtk_text_view_scroll_to_mark(GTK_TEXT_VIEW(app.log_view), mark, 0.0, TRUE, 0.0, 0.0);
        gtk_text_buffer_delete_mark(buffer, mark);
        break;
      }
      case EV_STATE:
        apply_state(event);
        break;
      case EV_IDLE:
        app.running = FALSE;
        gtk_widget_set_sensitive(app.install_button, TRUE);
        gtk_widget_set_sensitive(app.detect_button, TRUE);
        break;
      case EV_FINISH: {
        app.running = FALSE;
        gtk_widget_set_sensitive(app.install_button, TRUE);
        gtk_widget_set_sensitive(app.detect_button, TRUE);
        if (event->success) {
          gtk_label_set_text(GTK_LABEL(app.status),
                             "安装完成。请在系统设置中添加 Rime 输入法（fcitx5: fcitx5-configtool；ibus: ibus-setup）。");
          GdkRGBA rgba;
          gdk_rgba_parse(&rgba, "#1B7F3B");
          gtk_widget_override_color(app.status, GTK_STATE_FLAG_NORMAL, &rgba);
        } else {
          gtk_label_set_text(GTK_LABEL(app.status), "安装未完成，请根据日志排查后点击「开始安装」重试。");
          GdkRGBA rgba;
          gdk_rgba_parse(&rgba, "#C0392B");
          gtk_widget_override_color(app.status, GTK_STATE_FLAG_NORMAL, &rgba);
        }
        break;
      }
    }
    event_free(event);
  }
  return G_SOURCE_CONTINUE;
}

static void emit_idle(void) {
  Event *event = g_new0(Event, 1);
  event->type = EV_IDLE;
  g_mutex_lock(&app.lock);
  g_queue_push_tail(app.events, event);
  g_mutex_unlock(&app.lock);
}

static void emit_finish(gboolean success) {
  Event *event = g_new0(Event, 1);
  event->type = EV_FINISH;
  event->success = success;
  g_mutex_lock(&app.lock);
  g_queue_push_tail(app.events, event);
  g_mutex_unlock(&app.lock);
}

/* ------------------------------------------------------------------ */
/* Downloads                                                           */
/* ------------------------------------------------------------------ */

static const char *download_program(void) {
  int code = 0;
  char *out = run_capture("command -v curl >/dev/null 2>&1", &code);
  g_free(out);
  if (code == 0) return "curl";
  out = run_capture("command -v wget >/dev/null 2>&1", &code);
  g_free(out);
  return (code == 0) ? "wget" : NULL;
}

/* Download `url` to `dest`; returns TRUE on success. */
static gboolean download_to_file(const char *url, const char *dest) {
  const char *program = download_program();
  if (!program) return FALSE;
  char *command;
  if (g_str_equal(program, "curl"))
    command = g_strdup_printf("curl -fsSL --connect-timeout 20 --max-time 600 -o '%s' '%s'", dest, url);
  else
    command = g_strdup_printf("wget -q -T 20 -O '%s' '%s'", dest, url);
  int code = 0;
  char *out = run_capture(command, &code);
  g_free(out);
  g_free(command);
  if (code == 0 && file_exists(dest)) return TRUE;
  g_unlink(dest);
  return FALSE;
}

static gboolean network_available(void) {
  const char *probe = "https://cdn.jsdelivr.net/gh/rime/rime-wubi@master/wubi86.schema.yaml";
  gboolean ok = download_to_file(probe, "/tmp/.squirrel-setup-probe");
  if (ok) g_unlink("/tmp/.squirrel-setup-probe");
  return ok;
}

/* Very small JSON scraping of the shared manifest: enough for the fixed shape
 * we control, avoiding a JSON parser dependency. */
typedef struct {
  char *repo;
  char *mirror;
  char *git_ref;
  GPtrArray *files;   /* char* */
} PresetPackage;

static GPtrArray *presets_parse(void) {
  GPtrArray *packages = g_ptr_array_new();
  char **lines = g_strsplit(presets_json(NULL), "\n", -1);
  PresetPackage *current = NULL;

  for (char **line = lines; *line; ++line) {
    char *text = trim(*line);
    if (strstr(text, "\"packages\"")) continue;
    if (strstr(text, "\"name\"")) {
      current = g_new0(PresetPackage, 1);
      current->files = g_ptr_array_new_with_free_func(g_free);
      g_ptr_array_add(packages, current);
    }
    if (!current) continue;
    const char *keys[] = {"\"repo\"", "\"mirror\"", "\"ref\""};
    char **slots[] = {&current->repo, &current->mirror, &current->git_ref};
    for (int i = 0; i < 3; ++i) {
      if (strstr(text, keys[i])) {
        char *start = strchr(text, ':');
        if (!start) continue;
        start = strchr(start + 1, '"');
        if (!start) continue;
        char *end = strchr(start + 1, '"');
        if (!end) continue;
        *slots[i] = g_strndup(start + 1, (gsize)(end - start - 1));
      }
    }
    if (strstr(text, ".yaml\"")) {
      char *start = strchr(text, '"');
      if (!start) continue;
      char *end = strrchr(text, '"');
      if (!end || end <= start) continue;
      g_ptr_array_add(current->files, g_strndup(start + 1, (gsize)(end - start - 1)));
    }
  }
  g_strfreev(lines);
  return packages;
}

static GPtrArray *mirror_templates(void) {
  GPtrArray *templates = g_ptr_array_new_with_free_func(g_free);
  const char *start = strstr(presets_json(NULL), "\"mirrors\"");
  if (!start) return templates;
  const char *scan = start;
  for (;;) {
    scan = strstr(scan, "https://");
    if (!scan) break;
    const char *end = strchr(scan, '"');
    if (!end || (size_t)(end - scan) > 4000) break;
    g_ptr_array_add(templates, g_strndup(scan, (gsize)(end - scan)));
    scan = end + 1;
  }
  return templates;
}

/* ------------------------------------------------------------------ */
/* The five steps                                                      */
/* ------------------------------------------------------------------ */

static void step_detect(Platform *platform) {
  int index = step_index("detect");
  set_state(index, STEP_RUNNING, NULL);
  log_line("── 1/5 检测运行环境 / Detecting environment");

  log_line("%s · %s · 用户 %s",
           platform->distro_name ? platform->distro_name : "Linux",
#if defined(__aarch64__)
           "aarch64",
#elif defined(__x86_64__)
           "x86_64",
#else
           "unknown",
#endif
           g_get_user_name());

  if (fcitx5_rime_installed()) {
    log_ok("已安装 fcitx5-rime");
    platform->ime = "fcitx5";
  } else if (ibus_rime_installed()) {
    log_ok("已安装 ibus-rime");
    platform->ime = "ibus";
    g_free(platform->active_rime_dir);
    platform->active_rime_dir = g_strdup(platform->ibus_rime_dir);
  } else {
    log_warn("未检测到 Rime 引擎，将使用 %s 安装 fcitx5-rime。",
             platform->package_manager ? platform->package_manager : "系统包管理器");
  }

  log_line("Rime 用户目录：%s", platform->active_rime_dir);
  if (dir_exists(platform->active_rime_dir)) {
    char *build = path_join(platform->active_rime_dir, "build");
    if (dir_exists(build)) log_line("已存在编译产物 build/，本次部署会重新编译。");
    g_free(build);
  }
  log_line("包管理器：%s", platform->package_manager ? platform->package_manager : "未检测到");
  log_line("下载工具：%s", download_program() ? download_program() : "未检测到 curl/wget");

  if (network_available())
    log_ok("网络：可访问 plum 方案镜像（jsDelivr）");
  else
    log_warn("网络：jsDelivr 不可达，运行时将自动尝试其他镜像。");

  char *detail = g_strdup_printf("%s", platform->ime);
  set_state(index, STEP_DONE, detail);
  g_free(detail);
}

static void step_engine(Platform *platform) {
  int index = step_index("engine");
  set_state(index, STEP_RUNNING, NULL);
  log_line("── 2/5 安装 Rime 引擎 / Installing Rime engine");

  if (fcitx5_rime_installed() || ibus_rime_installed()) {
    log_line("Rime 引擎已安装，跳过安装。");
    set_state(index, STEP_SKIPPED, "已安装");
    return;
  }

  const char *packages = packages_for(platform->package_manager);
  char *inner = install_command(platform->package_manager, packages);
  if (!inner) {
    set_state(index, STEP_FAILED, "没有可用的包管理器");
    log_error("没有检测到受支持的包管理器（apt/dnf/pacman/zypper/apk），请手动安装 fcitx5-rime。");
    g_free(inner);
    return;
  }

  int has_pkexec = 0;
  char *probe = run_capture("command -v pkexec >/dev/null 2>&1", &has_pkexec);
  g_free(probe);
  char *command = g_strdup_printf("%s %s", has_pkexec ? "pkexec" : "sudo -A", inner);
  g_free(inner);
  log_line("执行：%s", command);
  log_line("需要管理员权限，请在弹出的授权窗口中确认…");

  int code = 0;
  char *output = run_capture(command, &code);
  g_free(command);
  if (output && *output) log_line("%s", trim(output));
  g_free(output);

  if (code != 0) {
    set_state(index, STEP_FAILED, "安装失败");
    log_error("Rime 引擎安装失败（退出码 %d），可手动安装后重新运行本程序。", code);
    return;
  }
  log_ok("fcitx5-rime 安装完成");
  set_state(index, STEP_DONE, "fcitx5-rime");
}

static void step_config(Platform *platform) {
  int index = step_index("config");
  set_state(index, STEP_RUNNING, NULL);
  log_line("── 3/5 写入用户配置 / Writing user config");

  g_mkdir_with_parents(platform->active_rime_dir, 0755);
  char *dest = path_join(platform->active_rime_dir, "default.custom.yaml");

  gsize existing_length = 0;
  char *existing = read_file(dest, &existing_length);
  gsize payload_length = 0;
  const char *payload = default_custom_yaml(&payload_length);

  if (existing && existing_length == payload_length &&
      memcmp(existing, payload, payload_length) == 0) {
    log_line("default.custom.yaml 已是最新内容，跳过写入。");
    set_state(index, STEP_SKIPPED, "已是最新");
    g_free(existing);
    g_free(dest);
    return;
  }
  if (existing) {
    char *stamp = g_strdup_printf("%s.bak-%s", dest, "backup");
    write_file(stamp, existing, existing_length);
    char *base = g_path_get_basename(stamp);
    log_line("已备份原配置 → %s", base);
    g_free(base);
    g_free(stamp);
  }
  g_free(existing);

  if (!write_file(dest, payload, payload_length)) {
    set_state(index, STEP_FAILED, "写入失败");
    log_error("写入 %s 失败：%s", dest, g_strerror(errno));
    g_free(dest);
    return;
  }
  log_ok("写入 %s", dest);
  log_line("  方案：五笔·拼音 / 朙月拼音·简体 / 五笔86");
  log_line("  中英切换：左 Shift（打字中途按下则编码原样上屏）");
  set_state(index, STEP_DONE, "default.custom.yaml");
  g_free(dest);
}

static void step_presets(Platform *platform) {
  int index = step_index("presets");
  set_state(index, STEP_RUNNING, NULL);
  log_line("── 4/5 安装词库与方案（plum 方案）/ Installing plum presets");

  g_mkdir_with_parents(platform->active_rime_dir, 0755);
  GPtrArray *packages = presets_parse();
  GPtrArray *mirrors = mirror_templates();

  int written = 0, skipped = 0, failed = 0;
  gsize total = 0;

  for (guint i = 0; i < packages->len; ++i) {
    PresetPackage *package = g_ptr_array_index(packages, i);
    if (!package->repo) continue;
    for (guint f = 0; f < package->files->len; ++f) {
      const char *file = g_ptr_array_index(package->files, f);
      char *dest = path_join(platform->active_rime_dir, file);

      if (file_exists(dest)) {
        GStatBuf st;
        if (g_stat(dest, &st) == 0 && st.st_size > 0) {
          log_line("  · %s 已存在（%.1f MB），跳过下载", file, st.st_size / 1048576.0);
          skipped++;
          g_free(dest);
          continue;
        }
      }

      gboolean ok = FALSE;
      for (guint m = 0; m < mirrors->len && !ok; ++m) {
        char *template = g_ptr_array_index(mirrors, m);
        char *url = g_strdup(template);
        str_replace(&url, "{repo}", package->repo);
        str_replace(&url, "{mirror}", package->mirror ? package->mirror : package->repo);
        str_replace(&url, "{ref}", package->git_ref ? package->git_ref : "master");
        str_replace(&url, "{file}", file);
        ok = download_to_file(url, dest);
        g_free(url);
      }
      if (ok) {
        GStatBuf st;
        g_stat(dest, &st);
        total += (gsize)st.st_size;
        written++;
        log_ok("  %s ← %s/%s (%.1f MB)", file, package->repo, file, st.st_size / 1048576.0);
      } else {
        failed++;
        log_error("  %s 下载失败（已尝试 %u 个镜像）", file, mirrors->len);
      }
      g_free(dest);
    }
  }

  g_ptr_array_free(packages, TRUE);
  g_ptr_array_free(mirrors, TRUE);

  if (written == 0 && skipped == 0) {
    set_state(index, STEP_FAILED, "下载失败");
    log_error("没有成功下载任何方案文件，请检查网络后重试。");
    return;
  }
  char *detail = g_strdup_printf("%d 个方案文件", written + skipped);
  log_ok("方案文件就绪：新写入 %d 个，跳过 %d 个，共 %.1f MB", written, skipped, total / 1048576.0);
  set_state(index, STEP_DONE, detail);
  g_free(detail);
  (void)failed;
}

static void step_deploy(Platform *platform) {
  int index = step_index("deploy");
  set_state(index, STEP_RUNNING, NULL);
  log_line("── 5/5 编译并启用输入法 / Building and enabling");

  int has_deployer = 0;
  char *probe = run_capture("command -v rime_deployer >/dev/null 2>&1", &has_deployer);
  g_free(probe);

  if (has_deployer == 0) {
    set_state(index, STEP_FAILED, "缺少 rime_deployer");
    log_error("未找到 rime_deployer，请先完成步骤 2（安装 fcitx5-rime）。");
    return;
  }

  const char *data_dirs[] = {"/usr/share/rime-data", "/usr/share/fcitx5/rime", NULL};
  const char *data_dir = NULL;
  for (int i = 0; data_dirs[i]; ++i) {
    if (dir_exists(data_dirs[i])) { data_dir = data_dirs[i]; break; }
  }
  if (!data_dir) data_dir = "/usr/share/rime-data";

  log_line("运行 rime_deployer --build（编译词库，通常需要 5–30 秒）…");
  char *command = g_strdup_printf(
      "cd '%s' && rime_deployer --build . '%s' .", platform->active_rime_dir, data_dir);
  int code = 0;
  char *output = run_capture(command, &code);
  g_free(command);
  if (output && *output) log_line("%s", trim(output));
  g_free(output);
  if (code != 0) {
    set_state(index, STEP_FAILED, "编译失败");
    log_error("rime_deployer 退出码 %d", code);
    return;
  }

  char *built = path_join(platform->active_rime_dir, "build/default.yaml");
  if (file_exists(built)) {
    gsize length = 0;
    char *text = read_file(built, &length);
    /* 只查 "commit_code" 子串太弱：任何一个键映射到 commit_code 都会让它通过。
       这里逐行确认 Shift_L 真的映射到 commit_code（左 Shift 中英切换）。 */
    gboolean shift_toggle = FALSE;
    if (text) {
      char **lines = g_strsplit(text, "\n", -1);
      for (char **line = lines; *line && !shift_toggle; line++) {
        g_strstrip(*line);
        if (strcmp(*line, "Shift_L: commit_code") == 0)
          shift_toggle = TRUE;
      }
      g_strfreev(lines);
    }
    if (shift_toggle)
      log_ok("编译产物 build/default.yaml：Shift_L: commit_code（左 Shift 中英切换）✓");
    else
      log_warn("警告：build/default.yaml 中 Shift_L 未映射到 commit_code，请检查 default.custom.yaml 是否生效。");
    g_free(text);
  } else {
    log_warn("警告：未生成 build/default.yaml，部署可能未成功。");
  }
  g_free(built);

  /* Restart the input method framework. Over ssh there is no session bus, so
   * provide XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS just like install-linux.sh. */
  if (g_str_equal(platform->ime, "ibus")) {
    int code2 = 0;
    char *out = run_capture("ibus restart >/dev/null 2>&1 || ibus-daemon --daemonize >/dev/null 2>&1", &code2);
    g_free(out);
    log_line("已重启 ibus（退出码 %d）", code2);
  } else {
    int code2 = 0;
    char *out = run_capture(
        "export XDG_RUNTIME_DIR=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"; "
        "export DBUS_SESSION_BUS_ADDRESS=\"${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}\"; "
        "pkill -x fcitx5 >/dev/null 2>&1; nohup fcitx5 -r -d >/dev/null 2>&1 &",
        &code2);
    g_free(out);
    log_line("已重启 fcitx5");
  }

  log_ok("Rime 已部署完成，输入法框架已重启。");
  set_state(index, STEP_DONE, "已部署");
}

typedef enum { MODE_DETECT, MODE_INSTALL } RunMode;

static gpointer installer_thread(gpointer data) {
  RunMode mode = GPOINTER_TO_INT(data);
  Platform platform;
  platform_init(&platform);

  for (int i = 0; i < app.step_count; ++i) set_state(i, STEP_PENDING, NULL);

  step_detect(&platform);
  if (mode == MODE_INSTALL) {
    step_engine(&platform);
    step_config(&platform);
    step_presets(&platform);
    step_deploy(&platform);

    gboolean success = app.steps[step_index("deploy")].state == STEP_DONE ||
                       app.steps[step_index("deploy")].state == STEP_SKIPPED;
    for (int i = 1; i < 5; ++i)
      if (app.steps[i].state == STEP_FAILED) success = FALSE;

    set_state(step_index("done"), success ? STEP_DONE : STEP_FAILED,
              success ? "" : "请查看上方日志后重试");
    if (success) log_ok("全部完成，可以开始使用了。");
    emit_finish(success);
  } else {
    emit_idle();
  }
  platform_free(&platform);
  return NULL;
}

/* ------------------------------------------------------------------ */
/* GTK callbacks                                                       */
/* ------------------------------------------------------------------ */

static void on_install(GtkButton *button, gpointer data) {
  (void)button; (void)data;
  if (app.running) return;
  app.running = TRUE;
  gtk_widget_set_sensitive(app.install_button, FALSE);
  gtk_widget_set_sensitive(app.detect_button, FALSE);
  gtk_label_set_text(GTK_LABEL(app.status), "正在安装，请勿关闭窗口…");
  g_thread_new("installer", installer_thread, GINT_TO_POINTER(MODE_INSTALL));
}

static void on_detect(GtkButton *button, gpointer data) {
  (void)button; (void)data;
  if (app.running) return;
  app.running = TRUE;
  gtk_widget_set_sensitive(app.install_button, FALSE);
  gtk_widget_set_sensitive(app.detect_button, FALSE);
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(app.log_view)), "", -1);
  g_thread_new("installer", installer_thread, GINT_TO_POINTER(MODE_DETECT));
}

static void on_reveal(GtkButton *button, gpointer data) {
  (void)button; (void)data;
  Platform platform;
  platform_init(&platform);
  g_mkdir_with_parents(platform.active_rime_dir, 0755);
  char *command = g_strdup_printf("xdg-open '%s' >/dev/null 2>&1 &", platform.active_rime_dir);
  int code = 0;
  char *out = run_capture(command, &code);
  g_free(out);
  g_free(command);
  platform_free(&platform);
}

static void on_quit(GtkButton *button, gpointer data) {
  (void)button; (void)data;
  gtk_main_quit();
}

static GtkWidget *build_step_row(int index, const char *id, const char *title, const char *subtitle) {
  GtkWidget *grid = gtk_grid_new();
  gtk_grid_set_column_spacing(GTK_GRID(grid), 10);
  gtk_grid_set_row_spacing(GTK_GRID(grid), 2);
  gtk_widget_set_margin_top(grid, 3);
  gtk_widget_set_margin_bottom(grid, 3);

  GtkWidget *glyph = gtk_label_new("○");
  gtk_widget_set_size_request(glyph, 24, -1);
  gtk_grid_attach(GTK_GRID(grid), glyph, 0, 0, 1, 1);

  GtkWidget *title_label = gtk_label_new(title);
  gtk_widget_set_size_request(title_label, 190, -1);
  gtk_label_set_xalign(GTK_LABEL(title_label), 0.0);
  gtk_grid_attach(GTK_GRID(grid), title_label, 1, 0, 1, 1);

  GtkWidget *subtitle_label = gtk_label_new(subtitle);
  gtk_label_set_xalign(GTK_LABEL(subtitle_label), 0.0);
  gtk_label_set_ellipsize(GTK_LABEL(subtitle_label), PANGO_ELLIPSIZE_END);
  gtk_label_set_selectable(GTK_LABEL(subtitle_label), TRUE);
  gtk_grid_attach(GTK_GRID(grid), subtitle_label, 2, 0, 1, 1);

  GtkWidget *detail = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(detail), 1.0);
  gtk_label_set_ellipsize(GTK_LABEL(detail), PANGO_ELLIPSIZE_END);
  gtk_grid_attach(GTK_GRID(grid), detail, 3, 0, 1, 1);

  app.steps[index].id = id;
  app.steps[index].title = title;
  app.steps[index].subtitle = subtitle;
  app.steps[index].glyph = glyph;
  app.steps[index].detail = detail;
  app.steps[index].state = STEP_PENDING;
  return grid;
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);

  g_mutex_init(&app.lock);
  app.events = g_queue_new();
  app.step_count = 6;

  app.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(app.window), "Squirrel 鼠鬚管安装程序 (Linux)");
  gtk_window_set_default_size(GTK_WINDOW(app.window), 880, 660);
  gtk_window_set_position(GTK_WINDOW(app.window), GTK_WIN_POS_CENTER);
  g_signal_connect(app.window, "destroy", G_CALLBACK(gtk_main_quit), NULL);

  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_margin_start(root, 20);
  gtk_widget_set_margin_end(root, 20);
  gtk_widget_set_margin_top(root, 18);
  gtk_widget_set_margin_bottom(root, 16);
  gtk_container_add(GTK_CONTAINER(app.window), root);

  GtkWidget *title = gtk_label_new("Squirrel 鼠鬚管 安装程序");
  gtk_label_set_xalign(GTK_LABEL(title), 0.0);
  PangoFontDescription *title_font = pango_font_description_from_string("Sans 22");
  pango_font_description_set_weight(title_font, PANGO_WEIGHT_SEMIBOLD);
  gtk_widget_override_font(title, title_font);
  pango_font_description_free(title_font);
  gtk_box_pack_start(GTK_BOX(root), title, FALSE, FALSE, 0);

  GtkWidget *subtitle = gtk_label_new("为 macOS / Windows / Linux 提供同一套 Rime 配置 · Linux 版 · v1.0.0");
  gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0);
  gtk_style_context_add_class(gtk_widget_get_style_context(subtitle), "dim-label");
  gtk_box_pack_start(GTK_BOX(root), subtitle, FALSE, FALSE, 0);

  GtkWidget *steps_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  static const char *ids[] = {"detect", "engine", "config", "presets", "deploy", "done"};
  static const char *titles[] = {"检测运行环境", "安装 Rime 引擎", "写入用户配置",
                                 "安装词库与方案", "编译并启用输入法", "完成"};
  static const char *subtitles[] = {
      "识别发行版、已安装的 Rime 与用户配置",
      "通过系统包管理器安装 fcitx5-rime（需要管理员权限）",
      "部署 default.custom.yaml（五笔 / 朙月拼音 / 左 Shift 切换）",
      "按 plum 方案下载 wubi86、五笔·拼音、朙月拼音词库",
      "运行 rime_deployer --build 并重启 fcitx5",
      "打开配置目录或开始使用"};
  for (int i = 0; i < 6; ++i)
    gtk_box_pack_start(GTK_BOX(steps_box), build_step_row(i, ids[i], titles[i], subtitles[i]), FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(root), steps_box, FALSE, FALSE, 0);

  app.progress = gtk_progress_bar_new();
  gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(app.progress), 0.0);
  gtk_box_pack_start(GTK_BOX(root), app.progress, FALSE, FALSE, 0);

  app.status = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(app.status), 0.0);
  gtk_box_pack_start(GTK_BOX(root), app.status, FALSE, FALSE, 0);

  GtkWidget *log_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  GtkWidget *log_title = gtk_label_new("安装日志 / Log");
  gtk_label_set_xalign(GTK_LABEL(log_title), 0.0);
  gtk_box_pack_start(GTK_BOX(log_box), log_title, FALSE, FALSE, 0);

  GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_widget_set_vexpand(scroll, TRUE);
  app.log_view = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(app.log_view), FALSE);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(app.log_view), FALSE);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(app.log_view), TRUE);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(app.log_view), GTK_WRAP_NONE);
  gtk_container_add(GTK_CONTAINER(scroll), app.log_view);
  GtkStyleContext *style = gtk_widget_get_style_context(scroll);
  gtk_style_context_add_class(style, "frame");
  gtk_box_pack_start(GTK_BOX(log_box), scroll, TRUE, TRUE, 0);
  gtk_box_pack_start(GTK_BOX(root), log_box, TRUE, TRUE, 0);

  GtkWidget *buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  app.install_button = gtk_button_new_with_label("开始安装");
  app.detect_button = gtk_button_new_with_label("重新检测");
  GtkWidget *reveal_button = gtk_button_new_with_label("打开配置目录");
  GtkWidget *quit_button = gtk_button_new_with_label("退出");
  GtkWidget *spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  g_signal_connect(app.install_button, "clicked", G_CALLBACK(on_install), NULL);
  g_signal_connect(app.detect_button, "clicked", G_CALLBACK(on_detect), NULL);
  g_signal_connect(reveal_button, "clicked", G_CALLBACK(on_reveal), NULL);
  g_signal_connect(quit_button, "clicked", G_CALLBACK(on_quit), NULL);
  gtk_box_pack_start(GTK_BOX(buttons), app.install_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(buttons), app.detect_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(buttons), reveal_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(buttons), spacer, TRUE, TRUE, 0);
  gtk_box_pack_start(GTK_BOX(buttons), quit_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(root), buttons, FALSE, FALSE, 0);

  gtk_widget_show_all(app.window);
  g_timeout_add(50, drain_events, NULL);
  app.running = TRUE;
  gtk_widget_set_sensitive(app.install_button, FALSE);
  gtk_widget_set_sensitive(app.detect_button, FALSE);
  g_thread_new("installer", installer_thread, GINT_TO_POINTER(MODE_DETECT));
  gtk_main();
  return 0;
}
