-- imk-e2e.applescript — IMK 客户端层真机端到端验证
--
-- 通过 System Events（具备辅助功能权限，合成事件不被系统丢弃）向真实 TextEdit
-- 投递按键，再用 TextEdit 自身的脚本接口读回文档文本——全程不依赖截图或像素。
--
-- 覆盖：五笔上屏、轻点左 Shift 切英文、再点切回中文。
-- 用例按当前默认方案 wubi86 的五笔码书写（见 ~/Library/Rime/wubi86.dict.yaml）。

set testKeys to {"wqiyvbg", "khklgy", "abc"}
set out to {}

tell application "TextEdit"
	activate
	set myDoc to make new document
end tell
delay 1.5

-- 1) 基础：中文态下五笔码应上屏；非五笔码原样直通
repeat with i from 1 to count of testKeys
	tell application "System Events"
		tell process "TextEdit"
			set frontmost to true
			keystroke (item i of testKeys)
			delay 0.6
			key code 49
			delay 0.9
		end tell
	end tell
	tell application "TextEdit"
		set cur to text of myDoc
		set text of myDoc to ""
	end tell
	set end of out to (out) & (item i of testKeys) & " + 空格 => [" & cur & "]" & linefeed
	delay 0.3
end repeat

-- 2) 左 Shift 三段式
set phaseZh to ""
set phaseEnShift to ""
set phaseBack to ""

-- A 中文态
tell application "System Events"
	tell process "TextEdit"
		set frontmost to true
		keystroke "wqiyvbg"
		delay 0.6
		key code 49
		delay 0.9
	end tell
end tell
tell application "TextEdit"
	set phaseZh to text of myDoc
	set text of myDoc to ""
end tell
delay 0.4

-- B 轻点左 Shift (key code 56) -> 英文态
tell application "System Events"
	tell process "TextEdit"
		set frontmost to true
		key code 56
		delay 0.9
		keystroke "abc"
		delay 0.7
	end tell
end tell
tell application "TextEdit"
	set phaseEnShift to text of myDoc
	set text of myDoc to ""
end tell
delay 0.4

-- C 再点左 Shift -> 回中文态
tell application "System Events"
	tell process "TextEdit"
		set frontmost to true
		key code 56
		delay 0.9
		keystroke "khklgy"
		delay 0.6
		key code 49
		delay 0.9
	end tell
end tell
tell application "TextEdit"
	set phaseBack to text of myDoc
end tell

tell application "TextEdit"
	close myDoc saving no
end tell

return (out as text) & "--- 左 Shift 切换 ---" & linefeed & ¬
	"A 中文态 wqiyvbg+空格   => [" & phaseZh & "]     期望 [你好]" & linefeed & ¬
	"B 点左Shift后 abc       => [" & phaseEnShift & "]     期望 [abc] 原样直通" & linefeed & ¬
	"C 再点左Shift khklgy+空格 => [" & phaseBack & "]     期望 [中国]"
