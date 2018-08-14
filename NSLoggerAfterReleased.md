# NSLogger在Swift環境下的行為
[NSLogger](https://github.com/fpillet/NSLogger)

最近有個案子為了debug logging方便，放棄了過去的自製Logger跟XCGLogger；改採用了NSLogger，有client app方便發版之後去檢視log。
但發版後卻發現發出去的的版本在client上看不到任何訊息...

追查後發現是release build configuration的差別，NSLogger在release時會不做任何事情；這個行為的實現又分成Objective-C跟Swift。

## Obj-C
`#if debug` 的應用，要取消掉就另外再定義一次marco即可

NSLogger.h
```Objective-C
#ifdef DEBUG
    #define NSLog(...)                      LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"NSLog", 0, __VA_ARGS__)
    #define LoggerError(level, ...)         LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Error", level, __VA_ARGS__)
    #define LoggerApp(level, ...)           LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"App", level, __VA_ARGS__)
    #define LoggerView(level, ...)          LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"View", level, __VA_ARGS__)
    #define LoggerService(level, ...)       LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Service", level, __VA_ARGS__)
    #define LoggerModel(level, ...)         LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Model", level, __VA_ARGS__)
    #define LoggerData(level, ...)          LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Data", level, __VA_ARGS__)
    #define LoggerNetwork(level, ...)       LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Network", level, __VA_ARGS__)
    #define LoggerLocation(level, ...)      LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Location", level, __VA_ARGS__)
    #define LoggerPush(level, ...)          LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Push", level, __VA_ARGS__)
    #define LoggerFile(level, ...)          LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"File", level, __VA_ARGS__)
    #define LoggerSharing(level, ...)       LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Sharing", level, __VA_ARGS__)
    #define LoggerAd(level, ...)            LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Ad and Stat", level, __VA_ARGS__)

#else
    #define NSLog(...)                      LogMessageCompat(__VA_ARGS__)
    #define LoggerError(...)                while(0) {}
    #define LoggerApp(level, ...)           while(0) {}
    #define LoggerView(...)                 while(0) {}
    #define LoggerService(...)              while(0) {}
    #define LoggerModel(...)                while(0) {}
    #define LoggerData(...)                 while(0) {}
    #define LoggerNetwork(...)              while(0) {}
    #define LoggerLocation(...)             while(0) {}
    #define LoggerPush(...)                 while(0) {}
    #define LoggerFile(...)                 while(0) {}
    #define LoggerSharing(...)              while(0) {}
    #define LoggerAd(...)                   while(0) {}

#endif
```

## Swift
swift底下就複雜了點，在swift時log是呼叫`logger.shared()`物件，基本上跟marcro無關，找文件跟issue也找不到頭緒，最後在[podspec](https://github.com/fpillet/NSLogger/blob/master/NSLogger.podspec)找到答案

```ruby
#
# NSLogger is automatically disabled in Release builds. If you want to keep it enabled in release builds,
# you can define a NSLOGGER_ENABLED flag which forces calling into the framework.
#
s.subspec 'Swift' do |ss|
    ss.dependency 'NSLogger/ObjC'
    ss.source_files = 'Client/iOS/*.swift'
    ss.pod_target_xcconfig = {
        'OTHER_SWIFT_FLAGS' => '$(inherited) -DNSLOGGER_DONT_IMPORT_FRAMEWORK',
        'OTHER_SWIFT_FLAGS[config=Release]' => '$(inherited) -DNSLOGGER_DONT_IMPORT_FRAMEWORK -DNSLOGGER_DISABLED'
    }
end
```


看到這邊又產生了另一個問題，要如何在swift中`#define NSLOGGER_ENABLED`呢？
在swift中`let NSLOGGER_ENABLED`是沒啥用的，只是在宣告變數 (https://stackoverflow.com/questions/24325477/how-to-use-a-objective-c-define-from-swift)
那就只能從`OTHER_SWIFT_FLAGS`下手，找到 [stackoverflow的討論](https://stackoverflow.com/questions/24003291/ifdef-replacement-in-the-swift-language)
在`podfile`中的`post_install`去做修改，大功告成啦

```ruby
post_install do | installer |
    installer.pods_project.targets.each do |target|
        if ['NSLogger'].include? target.name
            target.build_configurations.each do |config|
                config.build_settings['OTHER_SWIFT_FLAGS'] ||= ['$(inherited)']
                config.build_settings['OTHER_SWIFT_FLAGS'] << '"-DNSLOGGER_ENABLED"'
            end
        end
    end
end
```
