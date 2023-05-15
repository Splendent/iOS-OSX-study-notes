# 目的
將收到的指令轉成mac上的滑鼠操作
# 作法
原本是根據[FakeMouseEvent](https://github.com/raxcat/FakeMouseEvent)
走`IOHIDPostEvent(serviceConnection, NX_MOUSEMOVED, locPoint, &mouseEvent.data, kNXEventDataVersion, 0, kIOHIDSetRelativeCursorPosition);`
然後他....deprecated了
https://developer.apple.com/documentation/iokit/1555406-iohidpostevent
```
macOS 10.0–11.0 Deprecated
Mac Catalyst 13.0–14.2 Deprecated
```
替代的方案為`CGEvent`
```
let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentMousePointFromTopLeft(), mouseButton: .left)!
event.post(tap: .cghidEventTap)
````
又發現double click無法觸發，要加入clickState表數量，down跟up都要加
```
let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentMousePointFromTopLeft(), mouseButton: .left)!
event.setIntegerValueField(.mouseEventClickState, value: clickState)
event.post(tap: .cghidEventTap)
let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: FakeMouseSwift.currentMousePointFromTopLeft(), mouseButton: .left)!
event.setIntegerValueField(.mouseEventClickState, value: clickState)
event.post(tap: .cghidEventTap)
````


ref:
https://developer.apple.com/documentation/coregraphics/cgevent/1454356-init
https://stackoverflow.com/questions/1483657/performing-a-double-click-using-cgeventcreatemouseevent
