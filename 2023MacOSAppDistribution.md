# 目標
自行發佈DMG包裝正確Sign過的App，不走App store

# 說明
最早以前發佈App在App store之外是不用特別處理的，直到約2020左右Apple開始要求Notarize
`xcrun altool --notarize-app --primary-bundle-id ${bundle_id} -u ${notarize_username} -p ${notarize_password} -f ${pkgName} --verbose`

然而近期又說altool要退休了：＼
```
2023-03-13 11:12:10.009 *** Warning: altool has been deprecated for notarization and starting in late 2023 will no longer be supported by the Apple notary service. You should start using notarytool to notarize your software. (-1030)
```
改採用 notarytool

# 作法
使用過後覺得還行，其實比altool還好用
先建立身分
```
xcrun notarytool store-credentials ${credential_name} --apple-id ${apple_id} --team-id ${team_id} --password ${password}
```

然後簽證，加入`--wait`可以讓執行直到apple notarizing回覆完成後才算命令結束，不然要自己去query狀態才能知道notarize結果，對jenkins build來說算是方便許多
```
xcrun notarytool submit ${notarize_file_path} --keychain-profile ${credential_name} --wait
```
根據文件說明 notarize支援zip/pkg/dmg檔，但不支援.app檔案（資料夾）直接送出，需要注意一下
```
You can notarize an existing disk image, installer package, or ZIP archive containing your app.
```

# 參考
https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow

# 其他雜項
驗證notarize
`codesign -vvv --deep --strict`
要注意某些包裝/傳送方式可能造成codesign失效...
如某案子要求輸出為.iso檔案，就先將app包在zip中送去notarize
之後再將app以hidutil包成iso
後來回報被辨認為malware，用codesign檢查發現sign錯誤了
後來將app包成dmg，dmg送去notarize
dmg再包成iso檔案，驗證後sign正常，發給客戶也沒有被辨認成malware
## dmg轉成iso的方式
```
hdiutil convert dmgfile.dmg -format UDTO -o isofile.iso
```
## 損壞記錄
### 損壞的
```
SplendendeiMac:theApp Splenden$ codesign -vvv --deep --strict /Volumes/PlextorSSD/Users/Splenden/Downloads/theApp\ 3.app 
/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp 3.app: code object is not signed at all
In subcomponent: /Volumes/PlextorSSD/Users/Splenden/Downloads/theApp 3.app/Contents/Frameworks/SwiftyJSON.framework
```
### 正常的
```
SplendendeiMac:theApp Splenden$ codesign -vvv --deep --strict /Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app 
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/SwiftyJSON.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/SwiftyJSON.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WinnerWaveOSXUtility.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WinnerWaveOSXUtility.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/GoogleAnalyticsTracker.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/GoogleAnalyticsTracker.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/EZCastSitesManager.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/EZCastSitesManager.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/USBDeviceSwift.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/USBDeviceSwift.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WebViewJavascriptBridge.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WebViewJavascriptBridge.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/AetherLog.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/AetherLog.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/SimpleAES.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/SimpleAES.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/AudioInputCapture.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/AudioInputCapture.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/XCGLogger.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/XCGLogger.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/CocoaLumberjack.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/CocoaLumberjack.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/CocoaAsyncSocket.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/CocoaAsyncSocket.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WinnerWaveUtility.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WinnerWaveUtility.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/TPCircularBuffer.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/TPCircularBuffer.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/PromiseKit.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/PromiseKit.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/TransmitterKit.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/TransmitterKit.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/BytesMeter.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/BytesMeter.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/hidapi.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/hidapi.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/PINCache.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/PINCache.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/EZCastBitmask.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/EZCastBitmask.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/Alamofire.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/Alamofire.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WinnerWave_CocoaHTTPServer.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/WinnerWave_CocoaHTTPServer.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/Socket.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/Socket.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/ObjcExceptionBridging.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/ObjcExceptionBridging.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/AFNetworking.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/AFNetworking.framework/Versions/Current/.
--prepared:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/StarGate.framework/Versions/Current/.
--validated:/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app/Contents/Frameworks/StarGate.framework/Versions/Current/.
/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app: valid on disk
/Volumes/PlextorSSD/Users/Splenden/Downloads/theApp.app: satisfies its Designated Requirement
SplendendeiMac:theApp Splenden$
```
