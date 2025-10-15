#!/usr/bin/env bash
set -euxo pipefail

ROOT="$GITHUB_WORKSPACE"
ANKI_DIR="$ROOT/Anki-Android"

# 1) Clonar AnkiDroid (branch principal)
git clone --depth=1 --branch main https://github.com/ankidroid/Anki-Android.git "$ANKI_DIR"

# 2) Detectar o módulo do app (preferimos a pasta AnkiDroid; fallback por varredura)
if [ -d "$ANKI_DIR/AnkiDroid" ]; then
  APP_DIR="$ANKI_DIR/AnkiDroid"
else
  # procura o primeiro build.gradle(.kts) que tenha "namespace = \"com.ichi2.anki\"" ou aplique plugin de app via alias
  APP_GRADLE_CAND="$(grep -rl --include=build.gradle --include=build.gradle.kts -E 'namespace\s*=\s*"com\.ichi2\.anki"|android\.application' "$ANKI_DIR" | head -n1 || true)"
  if [ -z "$APP_GRADLE_CAND" ]; then
    echo "ERRO: não consegui localizar o módulo do app. Estrutura mudou. Me envie a listagem de pastas na raiz do repo." >&2
    exit 1
  fi
  APP_DIR="$(dirname "$APP_GRADLE_CAND")"
fi

APP_GRADLE_KTS="$APP_DIR/build.gradle.kts"
APP_GRADLE_GROOVY="$APP_DIR/build.gradle"
if [ -f "$APP_GRADLE_KTS" ]; then
  APP_GRADLE="$APP_GRADLE_KTS"
  EXT="kts"
elif [ -f "$APP_GRADLE_GROOVY" ]; then
  APP_GRADLE="$APP_GRADLE_GROOVY"
  EXT="gradle"
else
  echo "ERRO: não encontrei build.gradle(.kts) dentro de $APP_DIR" >&2
  exit 1
fi

echo "Módulo app: $APP_DIR  (arquivo: $APP_GRADLE)"

# 3) Injetar plugin do Spatial SDK (no bloco plugins)
if ! grep -q 'com.meta.spatial.plugin' "$APP_GRADLE"; then
  if [ "$EXT" = "kts" ]; then
    awk 'BEGIN{p=0}
    { print; if(!p && $0 ~ /plugins\s*\{/) { print "    id(\"com.meta.spatial.plugin\") version \"0.8.0\""; p=1 } }' \
      "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
  else
    awk 'BEGIN{p=0}
    { print; if(!p && $0 ~ /plugins\s*\{/) { print "    id \"com.meta.spatial.plugin\" version \"0.8.0\""; p=1 } }' \
      "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
  fi
fi

# 4) Adicionar dependências do Spatial SDK (em dependencies { })
if ! grep -q 'meta-spatial-sdk' "$APP_GRADLE"; then
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
  }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

# 5) Criar arquivos em src/debug (Manifest overlay + ids + Activity)
DBG_SRC="$APP_DIR/src/debug"
mkdir -p "$DBG_SRC/res/values" "$DBG_SRC/java/com/ichi2/anki/spatial"

# Manifest overlay (não remove o launcher existente; apenas adiciona o nosso)
cat > "$DBG_SRC/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools"
          package="com.ichi2.anki">
  <application>
    <meta-data
      android:name="com.oculus.supportedDevices"
      android:value="quest2|quest3|quest3s" />

    <activity
      android:name=".spatial.AnkiSpatialActivity"
      android:exported="true"
      android:resizeableActivity="true"
      android:configChanges="orientation|screenSize|screenLayout|keyboard|keyboardHidden|smallestScreenSize|uiMode">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>

    <activity
      android:name=".CollectionOpenActivity"
      tools:node="merge"
      tools:replace="allowEmbedded"
      android:allowEmbedded="true" />
    <activity
      android:name=".Reviewer"
      tools:node="merge"
      tools:replace="allowEmbedded"
      android:allowEmbedded="true" />
  </application>
</manifest>
EOF

# ids.xml
cat > "$DBG_SRC/res/values/ids.xml" <<'EOF'
<resources>
  <item name="panel_decks" type="id"/>
  <item name="panel_review" type="id"/>
</resources>
EOF

# Activity que registra e spawna os paineis 2D
cat > "$DBG_SRC/java/com/ichi2/anki/spatial/AnkiSpatialActivity.kt" <<'EOF'
package com.ichi2.anki.spatial

import android.os.Bundle
import androidx.activity.ComponentActivity
import com.meta.spatial.app.PanelRegistration
import com.meta.spatial.toolkit.ActivityPanelRegistration
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.scene.Entity
import com.meta.spatial.scene.Transform
import com.meta.spatial.math.Pose
import com.meta.spatial.math.Vector3
import com.ichi2.anki.CollectionOpenActivity
import com.ichi2.anki.Reviewer
import com.ichi2.anki.R

class AnkiSpatialActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val deckPanel: PanelRegistration = ActivityPanelRegistration(
            registrationId = R.id.panel_decks,
            classIdCreator = { CollectionOpenActivity::class.java },
            settingsCreator = {
                UIPanelSettings().apply {
                    minWidthMeters = 0.9f
                    minHeightMeters = 0.6f
                    canResize = true
                    canClose = true
                }
            }
        )

        val reviewPanel: PanelRegistration = ActivityPanelRegistration(
            registrationId = R.id.panel_review,
            classIdCreator = { Reviewer::class.java },
            settingsCreator = {
                UIPanelSettings().apply {
                    minWidthMeters = 0.9f
                    minHeightMeters = 0.6f
                    canResize = true
                    canClose = true
                }
            }
        )

        Entity.createPanelEntity(R.id.panel_decks, Transform(Pose(Vector3(0.0f, 0.0f, -1.2f))))
        Entity.createPanelEntity(R.id.panel_review, Transform(Pose(Vector3(0.8f, 0.0f, -1.2f))))
    }
}
EOF

# 6) Build debug (funciona para sideload no Quest)
cd "$ANKI_DIR"
./gradlew --no-daemon "$APP_DIR:assembleDebug" || ./gradlew --no-daemon :AnkiDroid:assembleDebug

# 7) Exportar APK(s)
mkdir -p "$ROOT/output-apk"
find "$ANKI_DIR" -type f -name "*.apk" -exec cp {} "$ROOT/output-apk/" \;
