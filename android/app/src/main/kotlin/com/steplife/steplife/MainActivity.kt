package com.steplife.steplife

import android.content.Intent
import android.os.Build
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "steplife/updater"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 用 FileProvider 拉起系统安装器安装 APK
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_PATH", "未提供 APK 路径", null)
                            return@setMethodCallHandler
                        }
                        // Android 8+ 需先授权「安装未知应用」，未授权时跳到系统设置引导
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val settingsIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(settingsIntent)
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "安装包不存在: $path", null)
                                return@setMethodCallHandler
                            }
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAIL", e.message, null)
                        }
                    }
                    // 当前设备主 ABI（如 arm64-v8a / armeabi-v7a / x86_64），用于选择对应架构安装包
                    "getAbi" -> {
                        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: ""
                        result.success(abi)
                    }
                    // 删除已下载的安装包（更新完成后清理）
                    "deleteApk" -> {
                        val path = call.argument<String>("path")
                        val ok = if (path.isNullOrBlank()) {
                            false
                        } else {
                            File(path).delete()
                        }
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
