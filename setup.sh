#!/bin/bash
# Run: bash setup.sh   (creates the whole GameBooster project in this folder)
set -e
mkdir -p ".github/workflows"
cat > ".github/workflows/build.yml" <<'GB_EOF'
name: Build APK

on:
  push:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: 8.9

      - name: Build debug APK
        run: gradle assembleDebug --stacktrace

      - uses: actions/upload-artifact@v4
        with:
          name: GameBooster-debug-apk
          path: app/build/outputs/apk/debug/*.apk
GB_EOF
mkdir -p "app"
cat > "app/build.gradle.kts" <<'GB_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.gamebooster"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.gamebooster"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
}
GB_EOF
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'GB_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:label="Game Booster"
        android:supportsRtl="true"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/DashboardScreen.kt" <<'GB_EOF'
package com.example.gamebooster

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

private fun fmt(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1) "%.1f GB".format(gb) else "%.0f MB".format(bytes / (1024.0 * 1024.0))
}

@Composable
fun DashboardScreen() {
    val context = LocalContext.current
    var snap by remember { mutableStateOf(SystemStats.read(context)) }

    // Refresh every second
    LaunchedEffect(Unit) {
        while (true) {
            snap = SystemStats.read(context)
            delay(1000)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Game Booster", style = MaterialTheme.typography.headlineMedium)

        StatCard(
            title = "RAM",
            value = "${fmt(snap.ramUsed)} / ${fmt(snap.ramTotal)}",
            fraction = snap.ramFraction
        )
        StatCard(
            title = "Storage",
            value = "${fmt(snap.storageUsed)} / ${fmt(snap.storageTotal)}",
            fraction = snap.storageFraction
        )
        StatCard(
            title = "Battery",
            value = "${snap.batteryPercent}%" + if (snap.charging) " (charging)" else "",
            fraction = snap.batteryPercent / 100f
        )

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Temperature", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text("Battery: %.1f °C".format(snap.batteryTempC))
                Text("Thermal status: ${snap.thermal}")
            }
        }
    }
}

@Composable
private fun StatCard(title: String, value: String, fraction: Float) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(4.dp))
            Text(value)
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { fraction.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/MainActivity.kt" <<'GB_EOF'
package com.example.gamebooster

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface { DashboardScreen() }
            }
        }
    }
}
GB_EOF
mkdir -p "app/src/main/java/com/example/gamebooster"
cat > "app/src/main/java/com/example/gamebooster/SystemStats.kt" <<'GB_EOF'
package com.example.gamebooster

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs

data class SystemSnapshot(
    val ramTotal: Long,
    val ramUsed: Long,
    val storageTotal: Long,
    val storageUsed: Long,
    val batteryPercent: Int,
    val batteryTempC: Float,
    val charging: Boolean,
    val thermal: String
) {
    val ramFraction: Float get() = if (ramTotal > 0) ramUsed.toFloat() / ramTotal else 0f
    val storageFraction: Float get() = if (storageTotal > 0) storageUsed.toFloat() / storageTotal else 0f
}

object SystemStats {

    fun read(context: Context): SystemSnapshot {
        // RAM
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }

        // Storage (internal)
        val stat = StatFs(Environment.getDataDirectory().path)
        val sTotal = stat.totalBytes
        val sUsed = sTotal - stat.availableBytes

        // Battery
        val bat = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = bat?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = bat?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) level * 100 / scale else 0
        val temp = (bat?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10f
        val status = bat?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        return SystemSnapshot(
            ramTotal = mi.totalMem,
            ramUsed = mi.totalMem - mi.availMem,
            storageTotal = sTotal,
            storageUsed = sUsed,
            batteryPercent = pct,
            batteryTempC = temp,
            charging = charging,
            thermal = thermalStatus(context)
        )
    }

    private fun thermalStatus(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "N/A"
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "Normal"
            PowerManager.THERMAL_STATUS_LIGHT -> "Light"
            PowerManager.THERMAL_STATUS_MODERATE -> "Moderate"
            PowerManager.THERMAL_STATUS_SEVERE -> "Severe"
            PowerManager.THERMAL_STATUS_CRITICAL -> "Critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "Emergency"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "Shutdown"
            else -> "Unknown"
        }
    }
}
GB_EOF
mkdir -p "."
cat > "build.gradle.kts" <<'GB_EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
}
GB_EOF
mkdir -p "."
cat > "gradle.properties" <<'GB_EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
GB_EOF
mkdir -p "."
cat > "settings.gradle.kts" <<'GB_EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "GameBooster"
include(":app")
GB_EOF
echo "Done! Project files created."
