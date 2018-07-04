# Install Kext in App on OSX

## 目的
原先安裝Kext是藉由PKG包裝去達成Kext安裝目的
```bash
pkgbuild --analyze --root /tmp/mykext "${BUILT_PRODUCTS_DIR}/$KEXT_PLIST"

pkgbuild --root /tmp/mykext --component-plist "${BUILT_PRODUCTS_DIR}/$KEXT_PLIST" --info "${PROJECT_DIR}/PackageInfo" --identifier $IDENTIFIER \
--version "$ShortVersion" --install-location "/System/Library/Extensions" "${BUILT_PRODUCTS_DIR}/Kexts_TEMP.pkg"
```
但安裝後還需要重開機才能啟動Kext，使用上不順暢；且目前的Kext也不需要重開機，使用Kextload即可立刻載入完成；決定改採用利用App去執行Script安裝Kext。

註：某些Kext必須要重開機才可以啟動，像是顯示卡驅動

## 流程
- App 啟動，檢查是否已安裝Kext (optional)
- 取得Admin privileges
- 安裝Kext

## 實作
這邊要先想要用什麼方式來執行Script，一般而言比較方便取得的有兩種方案，`NSAppleScript(AppleScript)`跟`NSTask(Bash)`；在取得權限的操作方面，AppleScirpt有較方便的方式，故此處採用AppleScript。

#### 檢查是否已安裝Kext
利用kextstat跟grep取得是否安裝，如已安裝則會得到`<NSAppleEventDescriptor: 'utxt'("INSTALLED")>` result
```swift
let kextStat = """
    do shell script "if [[ $(kextstat | grep \(kextBundleID) | grep -v grep) ]]; then echo INSTALLED; fi"
"""
let p = NSAppleScript.init(source:kextStat)
var errorDict: NSDictionary? = nil
if let reuslt = p?.executeAndReturnError(&errorDict) {
    print("OK")
    print(reuslt)
} else {
    print("FAIL")
    print(errorDict)
}
```

#### 取得Admin privileges
取得權限按照Apple文件，要用`Authorization Services`

`Authorization Services` ref
- 文件
	- https://developer.apple.com/documentation/security/authorization_services?language=objc
	- https://developer.apple.com/library/archive/documentation/Security/Conceptual/authorization_concepts/03authtasks/authtasks.html#//apple_ref/doc/uid/TP30000995-CH206-TP9
- sample 
	- https://developer.apple.com/library/archive/samplecode/EvenBetterAuthorizationSample/Introduction/Intro.html
	- https://stackoverflow.com/questions/10820125/nstask-execute-echo-command


**NSAppleScript** 則可以採用`do shell script with administrator privileges`的方式來讓AppleScript自行去跳出系統prompt問User權限。
`NSAppleScript` ref:
- https://developer.apple.com/library/archive/technotes/tn2084/_index.html


```swift
let install = """
    do shell script "sudo echo HELLO-SUDO" with administrator privileges
"""
let p = NSAppleScript.init(source:install)
var errorDict: NSDictionary? = nil
let alert = NSAlert.init()
if let result = p?.executeAndReturnError(&errorDict) {
    print("OK")
    print(reuslt)
} else {
    print("FAIL")
    print(errorDict)
}

```
若User拒絕授權，也會有error，訊息如下
```
Optional({
  NSAppleScriptErrorAppName = shellTest;
  NSAppleScriptErrorBriefMessage = "User canceled.";
  NSAppleScriptErrorMessage = "User canceled.";
  NSAppleScriptErrorNumber = "-128";
  NSAppleScriptErrorRange = "NSRange: {4, 215}";
})
```

#### 安裝Kext
將Kext移動到`/System/Library/Extensions`，然後執行`kextload`即可

kextload有幾點要求
- kext需要在`/System/Library/Extensions` 
	- 在其他地方會無法啟動，並清空啟動失敗的kext
- 需要 sudo/admin 權限
- 不需要 `chmod`/`chown` ?
	- 這點查了一下、試了兩台機器(OSX 10.13)都不需要改權限即可安裝，也沒找到明確的ref
	- 表示需要chmod/chown的 ref
		- http://osxdaily.com/2012/01/12/how-to-manually-install-kernel-extensions-in-mac-os-x/
	- 其他 ref
		- https://mymacbookmini.wordpress.com/tag/copy-kexts-manually-to-extensions-folder/
		- http://www.applegazette.com/mac/install-kexts-hackintosh-vanilla-macos/


```swift
let install = """
    do shell script "sudo echo \(kextPath)" with administrator privileges

    do shell script "sudo cp -R \(kextPath) \(kextInstallPath)" with administrator privileges

    do shell script "sudo kextload -v \(kextInstallPath)/\(kextName)" with administrator privileges
    do shell script "sudo kextutil \(kextInstallPath)/\(kextName)" with administrator privileges
"""
let p = NSAppleScript.init(source:install)
var errorDict: NSDictionary? = nil
let alert = NSAlert.init()
if let result = p?.executeAndReturnError(&errorDict) {
    alert.messageText = "kext installed"
    alert.informativeText = result.description
} else {
    alert.messageText = kext not installed"
    let message = (errorDict?["NSAppleScriptErrorBriefMessage"] as? String) ?? "Unknown issue."
    alert.informativeText = message
}
_ = alert.runModal()
```
script失敗，如安裝路徑錯誤
```
Optional({
  NSAppleScriptErrorAppName = shellTest;
  NSAppleScriptErrorBriefMessage = ...
  Requesting load of /Users/Splenden/Desktop/YOLOOOO/TEST_KEXT.kext.
  /Users/Splenden/Desktop/YOLOOOO/TEST_KEXT.kext failed to load - (libkern/kext) authentication failure (file ownership/permissions); check the system/kernel logs for errors or try kextutil(8).";
  NSAppleScriptErrorMessage = ...
  Requesting load of .... check the system/kernel logs for errors or try kextutil(8).";
  NSAppleScriptErrorNumber = 71;
  NSAppleScriptErrorRange = "NSRange: {718, 109}";
})
```

順道附上unistall script
```swift
let uninstall = """
  do shell script "if [[ $(kextstat | grep \(kextBundleID) | grep -v grep) ]]; then sudo kextunload -b \(kextBundleID); fi"
  do shell script "sudo rm -rf \(kextInstallPath)/\(kextName)" with administrator privileges
  do shell script "sudo rm -rf /Library/Receipts/\(kextBundleID).*" with administrator privileges
  do shell script "sudo rm -rf /var/db/receipts/\(kextBundleID).*" with administrator privileges
"""
```