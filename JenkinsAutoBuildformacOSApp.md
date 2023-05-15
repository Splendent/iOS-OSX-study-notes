# Jenkins Auto Build for macOS App

## 目的
利用Jenkins CI去自動發佈 macOS 上的 App；並且要正確的Code Sign，避免Gatekeeper阻擋App開啟。

## 實作
原本是利用Jenkins自帶的XCode plugin去建置，但是出來的App用`codesign -dv`去檢查發現沒有確實的Sign。於是改採用直接下`xcodebuild`命令的方式

### version
#### sed
```
#versioning, fuck agvtool, 2023
sed -i '' -e "s/MARKETING_VERSION \= [^\;]*\;/MARKETING_VERSION = ${SHORT_VERSION};/" {PROJECT}.xcodeproj/project.pbxproj
sed -i '' -e "s/CURRENT_PROJECT_VERSION \= [^\;]*\;/CURRENT_PROJECT_VERSION = ${TECHNICAL_VERSION_NUMBER};/" {PROJECT}.xcodeproj/project.pbxproj
```
*下列方法已經失效，目前apple新開的專案版本依據極其怪異*
目前僅確認在XCode IDE內輸入的可以有效更新版本號
#### agvtool
正規來說應該要用[agvtool](https://developer.apple.com/library/archive/qa/qa1827/_index.html)
但是apple的老樣子，出包
https://stackoverflow.com/questions/11737325/agvtool-new-version-and-what-version-do-not-correspond
https://stackoverflow.com/questions/72558951/agvtool-new-marketing-version-doesnt-work-on-xcode-13
#### python
版號設定這邊採用python的plist lib去處理；

```python
#!/usr/bin/python
import sys
import os
import plistlib

plistPath = 'Info.plist'
if os.path.isfile(plistPath):
	plist = plistlib.readPlist(plistPath)
	plist['CFBundleShortVersionString'] = os.environ['MARKETING_VERSION_NUMBER']
	plist['CFBundleVersion'] = os.environ['TECHNICAL_VERSION_NUMBER']
	#print plist
	plistlib.writePlist(plist, plistPath)
```

### xcodebuild
sign的時候會需要keychain，要先解鎖、exportArchive時需要exportOptions，可以參照App文件建立，或者先用XCode app archive輸出App一次，會順便生成ExportOptions.plist

ref: https://www.jianshu.com/p/e691a81d576c
ref: https://www.jianshu.com/p/e691a81d576c

```bash
mkdir "build"
security unlock-keychain -p ${password} ~/Library/Keychains/login.keychain
#Archive the app
xcodebuild -workspace "APP.xcworkspace" -config Release -scheme "APP"  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -archivePath "./build/APP.xcarchive" archive

#Export the archive as in the APP format
xcodebuild -archivePath "./build/APP.xcarchive" -exportArchive -exportPath "build" -exportOptionsPlist "ExportOptions.plist"
```

### dmg
採用dmg壓縮，一是因為.app實際上是資料夾，二是若採用zip，則有可能在解壓縮的時候因為解壓縮app沒有正確的sign過（由app store外取得且未sign）而被gatekeeper擋下。
建立dmg請見( https://ss64.com/osx/hdiutil.html )

`cp -R`/`cp -r`為不同命令，需要注意，若採用`cp -r`會產生sign錯誤的結果

ref: https://unix.stackexchange.com/questions/18712/difference-between-cp-r-and-cp-r-copy-command#comment104877_18718
ref: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html#//apple_ref/doc/uid/20002253-99920-BAJFEJFI
```bash
cd "build"
mkdir "dmg"
#zip will make app be unknown developer when unzip if unzip app is not signed
#zip -r "archive/APP.zip" "APP.app"
cp -R "APP.app" "dmg/APP.app"
hdiutil create -fs HFS+ -srcfolder "dmg" -volname "APP" "APP.dmg"
```

### 其他

[Notarize](2023MacOSAppDistributionInDMG.md)

codesign 驗證
```
codesign -dv APP.app
```

Apple官方參考
https://help.apple.com/xcode/mac/current/#/dev033e997ca
