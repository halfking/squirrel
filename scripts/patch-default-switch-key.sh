#!/bin/sh
#  patch-default-switch-key.sh — make the LEFT SHIFT key the default
#  Chinese/English toggle in a librime `default.yaml`.
#
#  Why this is a build step and not a hand edit of data/plum/default.yaml:
#  that file is generated. `make plum-data` copies plum/output/* into data/plum/,
#  and plum/output is refreshed from upstream rime-prelude, which ships
#  `Shift_L: inline_ascii`. So a manual edit is silently reverted the next time
#  the plum data is regenerated — and data/plum/ is gitignored, so the edit was
#  never in version control either. Patching here makes the setting reproducible
#  for anyone who builds the tree.
#
#  Why commit_code and not upstream's inline_ascii:
#  inline_ascii is a one-shot ASCII "symbol" mode that expires on the next
#  keypress, so the key does not behave as a persistent Chinese/English switch.
#  commit_code flips ascii_mode immediately, and when pressed mid-composition it
#  commits the text as typed instead of discarding it. This is the behaviour the
#  user asked for: press left Shift, and typing goes from abc to Chinese or back.
#
#  Only the left Shift entry inside ascii_composer/switch_key is rewritten.
#  Every other switch_key entry (Shift_R, Control_L/R, Caps_Lock, Eisu_toggle)
#  is left exactly as upstream has it, and so is the rest of the file.
#
#  Idempotent: a second run is a no-op. If the switch_key block is missing the
#  script fails loudly rather than reporting success on an unpatched file.
#
#  Usage: scripts/patch-default-switch-key.sh <path/to/default.yaml>
set -eu

yaml="${1:?usage: patch-default-switch-key.sh <path/to/default.yaml>}"
[ -f "$yaml" ] || {
  echo "patch-default-switch-key: not found: $yaml" >&2
  exit 1
}

tmp="$yaml.tmp.$$"
trap 'rm -f "$tmp"' EXIT

awk '
  BEGIN {
    COMMENT = "    # 左 Shift 切换中英文（commit_code：立即切换；编码中途按下则原样上屏）"
  }
  # Only touch the Shift_L entry that lives inside the switch_key block.
  /^[[:space:]]*switch_key:[[:space:]]*$/ { in_switch = 1; print; last = $0; next }
  in_switch && /^[^[:space:]]/ { in_switch = 0 }        # block ended
  in_switch && /^[[:space:]]*Shift_L:[[:space:]]*/ {
    # Re-emitting the comment unconditionally would duplicate it on every run.
    if (last != COMMENT) print COMMENT
    print "    Shift_L: commit_code"
    last = "    Shift_L: commit_code"
    next
  }
  { print; last = $0 }
' "$yaml" > "$tmp"

mv "$tmp" "$yaml"
trap - EXIT

# A missing switch_key block would leave the file untouched; fail instead of
# claiming success, so a silently unpatched engine can never ship.
grep -q '^[[:space:]]*Shift_L:[[:space:]]*commit_code' "$yaml" || {
  echo "patch-default-switch-key: patch did not take effect in $yaml" >&2
  exit 1
}

echo "patch-default-switch-key: Shift_L = commit_code in $yaml"
