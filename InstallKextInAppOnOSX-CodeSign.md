# Kext Signing

## 目的
在Install Kext In App on OSX (InstallKextInAppOnOSX.md) 中製作的App，Archive->Export as Developer App後發生無法安裝Kext的問題，開始了有關於Kext的研究

## 實作
首先看失敗訊息
```
$ sudo kextload -t /System/Library/Extensions/badKext.kext/
Notice: -print-diagnostics (-t) ignored; use kextutil(8) to test kexts.
/System/Library/Extensions/badKext.kext failed to load - (libkern/kext) not loadable (reason unspecified); check the system/kernel logs for errors or try kextutil(8).
```
沒說明為什麼，找Kextutil(8)，在現在的osx上面也跑不了。只能從其他方向下手
看到這兩篇 WavTap(https://github.com/pje/WavTap/issues/60)、 opcm(https://github.com/opcm/pcm/issues/30) 說是High Serria的 Kext保護機制(https://developer.apple.com/library/archive/technotes/tn2459/_index.html) 造成。
用 `csrutil disable` 解除限制，不過怎麼想都不覺得關閉某些機制是恰當的處理方式；而且在debug時安裝是沒問題的，安裝時也沒出現SIP的警告，問題在於export出來的app無法安裝。

試著查明export的kext跟debug的有什麼差別，用file diff檢查後發現兩者kext不相同；推測export有經過處理，通常來說處理都是signing相關，用`codesign -dv`來看，發現sign改動過，推測是export的時候又sign了一次。

改用export出來的app跟事先準備好沒改過的kext去安裝，沒有問題:)
確認問題在於kext的sign；接下來就是各種sign的測試。

首先用`codesign --remove-sign`去把sign砍掉，後用`codesign -dv`確認sign已經去掉；再用`codesign -s "Developer ID App: my.com.pany" theKext.kext`去簽，簽完後發現還是無法安裝。

改採用Kext的XCode proj不用任何sign去輸出kext，sign的方式則讓XCode export時讓他自動sign，如此一來便成功了！

這邊順便附上當初測試sign的結果表格

|     移除sign\簽sign    | codesign -s | xcode export |
|:----------------------:|:-----------:|:------------:|
| codesign --remove-sign |      X      |       X      |
|  xcode don't codesign  |      X      |       O      |



後來又手養了一下，想看看用不同的sign能不能過，果不其然的連xcode export時的sign都無法通過；參考相關資源後確認，要做kext的sign要先去跟apple申請。

ref: 

https://stackoverflow.com/questions/26830800/cant-sign-kext-in-mavericks-yosemite

https://stackoverflow.com/questions/26283158/codesigning-kext-with-kext-enabled-certificate-fails-during-kextload-code-sign

https://forums.developer.apple.com/thread/18019


申請網址:

https://developer.apple.com/contact/kext/

