# Kotlin Android：SAF 选择目录、逐级浏览、删除文件

## 简介

在原生 Android（Kotlin）里演示：只用**系统目录选择器**授权一个文件夹，在应用内列出**当前目录**下的子文件夹与文件；点击文件夹进入下一层；仅对**文件**在右侧显示删除按钮，删除前弹出对话框确认。

## 快速开始

### 环境要求

JDK 17（与 `app/build.gradle` 中 `jvmTarget` 一致）、Android SDK。可用 Android Studio 打开工程，也可仅命令行构建。

### 生成 Debug APK（命令行）

工程根目录已包含 Gradle Wrapper（`gradlew`），可直接：

```bash
cd kotlin-android-saf-directory-scan-delete-demo
./gradlew :app:assembleDebug
```

成功后 APK 一般在：

`app/build/outputs/apk/debug/app-debug.apk`

安装到设备：

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 用 Android Studio

打开本目录 → 同步 Gradle → Run。生成 release 包可在 AS 中选 Build APK(s) 或配置签名后 `assembleRelease`。

## 概念讲解

### 第一部分：为什么选择目录是 SAF

从 Android 10 起，应用通常不能直接遍历外置存储的任意路径。让用户通过 `OpenDocumentTree` 选中目录并取得持久化 URI 权限，是访问「用户指定地点」的常见方式。

### 第二部分：逐级浏览

授权后得到目录树根 `DocumentFile`。本 Demo 用栈保存从根到当前文件夹的路径：点子文件夹入栈，「返回上一级」出栈，列表只展示**当前层**的子文件夹与文件。

### 第三部分：删除与确认

对文件调用 `DocumentFile.delete()`，删除前用 `AlertDialog` 二次确认。Android 没有整盘统一的「回收站」API；删除一般不可恢复，请勿在重要目录上试验。

## 完整讲解（中文）

先点「选择目录」，系统在文档界面里让你挑一个文件夹，相当于授权本应用读写这棵目录树。列表里文件夹带 📁 前缀，点一项就进入该子目录；想回到上层用「返回上一级」。只有普通文件右侧会出现「删除」；按删除必经过确认框，避免误触。

务必用测试目录练习，避免误删。
