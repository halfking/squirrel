#!/usr/bin/env bash
# 菜单栏输入法图标自助验收：截屏 + 像素分析图标槽位。
# 用法（注销重登后运行）： bash tools/verify-icon.sh
set -uo pipefail
cd "$(dirname "$0")/.."
SHOT=/tmp/icon-verify.png
screencapture -x "$SHOT" 2>/dev/null
python3 - "$SHOT" <<'PYEOF'
import zlib, struct, sys

def load_png(path):
    data = open(path,'rb').read()
    pos, w, h, bd, ct = 8,0,0,0,0
    idat = b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]; typ = data[pos+4:pos+8]
        if typ == b'IHDR':
            w,h,bd,ct = struct.unpack('>IIBB', data[pos+8:pos+18])
        elif typ == b'IDAT':
            idat += data[pos+8:pos+8+ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0:1,2:3,4:2,6:4}[ct]
    stride = w*ch
    rows=[]; prev=bytearray(stride); ptr=0
    for y in range(h):
        f=raw[ptr]; ptr+=1
        line=bytearray(raw[ptr:ptr+stride]); ptr+=stride
        if f==1:
            for i in range(ch,stride): line[i]=(line[i]+line[i-ch])&255
        elif f==2:
            for i in range(stride): line[i]=(line[i]+prev[i])&255
        elif f==3:
            for i in range(stride):
                a=line[i-ch] if i>=ch else 0
                line[i]=(line[i]+((a+prev[i])>>1))&255
        elif f==4:
            for i in range(stride):
                a=line[i-ch] if i>=ch else 0
                b=prev[i]; c=prev[i-ch] if i>=ch else 0
                p=a+b-c; pa=abs(p-a); pb=abs(p-b); pc=abs(p-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i]=(line[i]+pr)&255
        rows.append(bytes(line)); prev=line
    return w,h,ch,rows

w,h,ch,rows = load_png(sys.argv[1])
# 扫描菜单栏右半区（y 3..24），找连续浅色块（图标特征：宽14-40px、亮像素>=70%）
best=None
run=0
for x in range(1100, w):
    bright=sum(1 for y in range(3,24,2) if sum(rows[y][x*ch:x*ch+3])/3>190)
    if bright>=8: run+=1
    else:
        if 14<=run<=40: best=(x-run,run)
        run=0
if 14<=run<=40: best=(w-run,run)
if best:
    print(f"PASS 检测到图标槽浅色块（x={best[0]} 宽={best[1]}px）——图标已恢复")
else:
    print("FAIL 未检测到图标槽浅色块——图标仍缺失；若已重登过，运行 bash tools/switch-menu-icon.sh 后再重登一次")
PYEOF
