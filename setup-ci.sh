#!/usr/bin/env bash
set -euxo pipefail

ROOT="$GITHUB_WORKSPACE"
ANKI_DIR="$ROOT/Anki-Android"
APP_DIR="$ANKI_DIR/AnkiDroid"   # módulo app oficial do projeto

# 1) Clonar AnkiDroid (branch principal)
git clone --depth=1 --branch main https://github.com/ankidroid/Anki-Android.git "$ANKI_DIR"

# 2) GARANTIR que NÃO há include de :spatial-shell no settings (remover se algum sobrou)
if [ -f "$ANKI_DIR/settings.gradle.kts" ]; then
  sed -i '/include(":spatial-shell")/d' "$ANKI_DIR/settings.gradle.kts"
else
  sed -i '/include(":spatial-shell")/d' "$ANKI_DIR/settings.gradle" || true
fi

# 3) Apontar para o módulo de app real
if [ ! -f "$APP_DIR/build.gradle.kts" ]; then
  echo "ERRO: não achei $APP_DIR/build.gradle.kts (layout do repo mudou?)" >&2
  exit 1
fi

APP_GRADLE="$APP_DIR/build.gradle.kts"

# 4) Injetar plugin do Spatial SDK no módulo :AnkiDroid (se ainda não existir)
if ! grep -q 'com.meta.spatial.plugin' "$APP_GRADLE"; then
  awk 'BEGIN{p=0}
  {
    print
    if (!p && $0 ~ /plugins\s*\{/) {
      print "    id(\"com.meta.spatial.plugin\") version \"0.8.0\""
      p=1
    }
  }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

# 5) Adicionar dependências do Spatial SDK (se ainda não existirem)
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

# 6) Criar flavor 'spatial' (se não houver flavors)
if ! grep -q 'productFlavors' "$APP_GRADLE"; then
  awk '{
    print
    if ($0 ~ /android\s*\{/) {
      print "    flavorDimensions += \"distribution\""
      print "    productFlavors {"
      print "        create(\"mobile\") { dimension = \"distribution\" }"
      print "        create(\"spatial\") { dimension = \"distribution\" }"
      print "    }"
    }
  }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
else
  # Se já houver flavors, apenas garantimos que exista o 'spatial'
  if ! grep -q 'create("spatial")' "$APP_GRADLE"; then
    echo "ATENÇÃO: já existem flavors, mas sem 'spatial'. Você pode adicionar manualmente se o build falhar."
  fi
fi

# 7) Criar arquivos do flavor 'spatial' (Manifest overlay, ids.xml e Activity)
SPATIAL_SRC="$APP_DIR/src/spatial"
mkdir -p "$SPATIAL_SRC/AndroidManifestOverlay" "$SPATIAL_SRC/res/values" "$SPATIAL_SRC/java/com/ichi2/anki/spatial"

# 7.1) Manifest overlay com allowEmbedded e Activity de entrada
cat > "$SPATIAL_SRC/AndroidManifestOverlay/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools"
          package="com.ichi2.anki">
  <application>
    <!-- Suporte explícito a Quest 2/3/3S -->
    <meta-data
      android:name="com.oculus.supportedDevices"
      android:value="quest2|quest3|quest3s" />

    <!-- Activity imersiva que registra/spawna os paineis 2D -->
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

    <!-- Habilitar embed das telas do Anki -->
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

# 7.2) ids.xml para registrations
cat > "$SPATIAL_SRC/res/values/ids.xml" <<'EOF'
<resources>
    <item name="panel_decks" type="id"/>
    <item name="panel_review" type="id"/>
</resources>
EOF

# 7.3) Activity que registra e spawna os painéis (baseado em Activities existentes)
cat > "$SPATIAL_SRC/java/com/ichi2/anki/spatial/AnkiSpatialActivity.kt" <<'EOF'
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

        // Criar (spawn) os paineis em frente ao usuário (~1,2 m)
        Entity.createPanelEntity(R.id.panel_decks, Transform(Pose(Vector3(0.0f, 0.0f, -1.2f))))
        Entity.createPanelEntity(R.id.panel_review, Transform(Pose(Vector3(0.8f, 0.0f, -1.2f))))
    }
}
EOF

# 8) Build da variant :AnkiDroid:spatialDebug
cd "$ANKI_DIR"
./gradlew --no-daemon :AnkiDroid:assembleSpatialDebug

# 9) Copiar APK(s) para a saída do pipeline
mkdir -p "$ROOT/output-apk"
find "$ANKI_DIR" -type f -name "*.apk" -exec cp {} "$ROOT/output-apk/" \;
