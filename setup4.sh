#!/bin/bash
# Adds a custom app icon. Run: bash setup4.sh
set -e
mkdir -p app/src/main/res/values app/src/main/res/drawable app/src/main/res/mipmap-anydpi-v26

cat > app/src/main/res/values/ic_launcher_background.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0B1220</color>
</resources>
EOF

cat > app/src/main/res/drawable/ic_launcher_foreground.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <!-- outer ring -->
    <path
        android:pathData="M54,26 A28,28 0 1 1 53.99,26 Z"
        android:strokeColor="#22D3EE"
        android:strokeWidth="4"
        android:fillColor="#00000000" />

    <!-- lightning bolt -->
    <path
        android:pathData="M58,33 L44,56 L52,56 L49,75 L65,50 L57,50 L61,33 Z"
        android:fillColor="#A3E635" />
</vector>
EOF

cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
EOF

cp app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml

if ! grep -q 'android:icon' app/src/main/AndroidManifest.xml; then
  sed -i 's|android:allowBackup="true"|android:allowBackup="true"\n        android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"|' app/src/main/AndroidManifest.xml
fi
echo "Icon added!"
