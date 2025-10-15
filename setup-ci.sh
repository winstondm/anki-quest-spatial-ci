#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
ANKI_DIR="$ROOT/Anki-Android"

echo ">> Clonando AnkiDroid (main) ..."
rm -rf "$ANKI_DIR"
git clone --depth=1 --branch main https://github.com/ankidroid/Anki-Android.git "$ANKI_DIR"

APP_DIR="$ANKI_DIR/AnkiDroid"
GRADLE_KTS="$APP_DIR/build.gradle.kts"
GRADLE_GROOVY="$APP_DIR/build.gradle"

if [[ -f "$GRADLE_KTS" ]]; then
  APP_GRADLE="$GRADLE_KTS"
  EXT="kts"
elif [[ -f "$GRADLE_GROOVY" ]]; then
  APP_GRADLE="$GRADLE_GROOVY"
  EXT="gradle"
else
  echo "ERRO: Não achei build.gradle(.kts) em $APP_DIR"
  exit 1
fi

echo ">> Injetando plugin Spatial SDK (com.meta.spatial.plugin) em $APP_GRADLE ..."
if [[ "$EXT" == "kts" ]]; then
  # adiciona o plugin dentro do bloco plugins { }
  awk 'BEGIN{p=0}
    {
      print
      if (!p && $0 ~ /plugins\s*\{/) {
        print "    id(\"com.meta.spatial.plugin\") version \"0.8.0\""
        p=1
      }
    }' "$APP_GRADLE" > "$APP_GRADLE.tmp"
  mv "$APP_GRADLE.tmp" "$APP_GRADLE"
else
  # Groovy: idem
  awk 'BEGIN{p=0}
    {
      print
      if (!p && $0 ~ /plugins\s*\{/) {
        print "    id \"com.meta.spatial.plugin\" version \"0.8.0\""
        p=1
      }
    }' "$APP_GRADLE" > "$APP_GRADLE.tmp"
  mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

echo ">> Garantindo dependências do Spatial SDK ..."
if ! grep -q 'com.meta.spatial:meta-spatial-sdk' "$APP_GRADLE"; then
  if [[ "$EXT" == "kts" ]]; then
    awk 'BEGIN{d=0}
      {
        print
        if (!d && $0 ~ /dependencies\s*\{/) {
          print "    implementation(\"com.meta.spatial:meta-spatial-sdk:0.8.0\")"
          print "    implementation(\"com.meta.spatial:meta-spatial-sdk-toolkit:0.8.0\")"
          print "    implementation(\"com.meta.spatial:meta-spatial-sdk-vr:0.8.0\")"
          print "    implementation(\"com.meta.spatial:meta-spatial-sdk-physics:0.8.0\")"
          d=1
        }
      }' "$APP_GRADLE" > "$APP_GRADLE.tmp"
  else
    awk 'BEGIN{d=0}
      {
        print
        if (!d && $0 ~ /dependencies\s*\{/) {
          print "    implementation \"com.meta.spatial:meta-spatial-sdk:0.8.0\""
          print "    implementation \"com.meta.spatial:meta-spatial-sdk-toolkit:0.8.0\""
          print "    implementation \"com.meta.spatial:meta-spatial-sdk-vr:0.8.0\""
          print "    implementation \"com.meta.spatial:meta-spatial-sdk-physics:0.8.0\""
          d=1
        }
      }' "$APP_GRADLE" > "$APP_GRADLE.tmp"
  fi
  mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

echo ">> Criando fontes/res de DEBUG para atividade imersiva + painel ..."
DBG_JAVA="$APP_DIR/src/debug/java/com/ichi2/anki/spatial"
DBG_RES_VAL="$APP_DIR/src/debug/res/values"
DBG_MANIFEST_DIR="$APP_DIR/src/debug"
mkdir -p "$DBG_JAVA" "$DBG_RES_VAL" "$DBG_MANIFEST_DIR"

cat > "$DBG_RES_VAL/ids.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <item name="anki_panel" type="id"/>
</resources>
XML

cat > "$DBG_MANIFEST_DIR/AndroidManifest.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <!-- Atividade imersiva só no build debug, com LAUNCHER para facilitar teste no Quest -->
        <activity
            android:name="com.ichi2.anki.spatial.AnkiSpatialActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Algumas telas do Anki podem ser abertas embutidas como painel (quando aplicável) -->
        <!-- Se não existir a declaração original, o tools:replace é simplesmente ignorado -->
        <!-- (Aviso no build é normal) -->
    </application>
</manifest>
XML

cat > "$DBG_JAVA/AnkiSpatialActivity.kt" <<'KOT'
package com.ichi2.anki.spatial

import android.content.Intent
import com.meta.spatial.toolkit.AppSystemActivity
import com.meta.spatial.toolkit.PanelRegistration
import com.meta.spatial.toolkit.IntentPanelRegistration
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.DpDisplayOptions
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.createPanelEntity   // <<-- IMPORT NECESSÁRIO
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.core.Quaternion
import com.ichi2.anki.R

class AnkiSpatialActivity : AppSystemActivity() {

    override fun registerPanels(): List<PanelRegistration> {
        val ankiIntentPanel = IntentPanelRegistration(
            registrationId = R.id.anki_panel,
            intentCreator = { _ ->
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                } ?: Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    `package` = packageName
                }
            },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = 1.0f, height = 0.7f),
                    display = DpDisplayOptions(width = 1000f, height = 700f)
                )
            }
        )
        return listOf(ankiIntentPanel)
    }

    override fun onSceneReady() {
        super.onSceneReady()
        // Cria o painel ~1,2 m à frente
        Entity.createPanelEntity(
            R.id.anki_panel,
            Transform(Pose(Vector3(0f, 1.3f, -1.2f), Quaternion(1f, 0f, 0f, 0f)))
        )
    }
}
KOT

echo ">> Compilando variante debug Play (gera APK instalável) ..."
cd "$ANKI_DIR"
/usr/bin/env bash ./gradlew --no-daemon :AnkiDroid:assemblePlayDebug

echo ">> Saída de APKs:"
find "$APP_DIR/build/outputs" -type f -iname "*.apk" -print

mkdir -p "$ROOT/output-apk"
find "$APP_DIR/build/outputs" -type f -iname "*.apk" -exec cp {} "$ROOT/output-apk/" \;
