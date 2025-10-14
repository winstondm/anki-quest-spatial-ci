#!/usr/bin/env bash
set -euxo pipefail

ROOT="$GITHUB_WORKSPACE"
ANKI_DIR="$ROOT/Anki-Android"

# 1) Clonar o AnkiDroid (branch principal)
git clone --depth=1 --branch main https://github.com/ankidroid/Anki-Android.git "$ANKI_DIR"

# 2) Remover qualquer include antigo de :spatial-shell (se existir)
if [ -f "$ANKI_DIR/settings.gradle.kts" ]; then
  sed -i '/include(":spatial-shell")/d' "$ANKI_DIR/settings.gradle.kts" || true
fi
if [ -f "$ANKI_DIR/settings.gradle" ]; then
  sed -i '/include(":spatial-shell")/d' "$ANKI_DIR/settings.gradle" || true
fi

# 3) Detectar AUTOMATICAMENTE o módulo de app (tem o plugin com.android.application)
APP_GRADLE="$(grep -rl --include=build.gradle --include=build.gradle.kts -E '^\s*plugins\s*\{[^}]*id\((\"|\x27)com\.android\.application(\"|\x27)\)' "$ANKI_DIR" | head -n1 || true)"
if [ -z "$APP_GRADLE" ]; then
  echo "ERRO: não achei build.gradle(.kts) com 'com.android.application' no repo do Anki." >&2
  echo "Estrutura mudou. Me envie a listagem de módulos (pasta raiz) que eu ajusto." >&2
  exit 1
fi
APP_DIR="$(dirname "$APP_GRADLE")"
APP_MODULE=":${APP_DIR##*/}"
echo "Módulo de app detectado: $APP_MODULE ($APP_GRADLE)"

# Helper: é KTS?
EXT="${APP_GRADLE##*.}"   # kts ou gradle

# 4) Injetar plugin do Spatial SDK no módulo do app
if ! grep -q 'com.meta.spatial.plugin' "$APP_GRADLE"; then
  if [ "$EXT" = "kts" ]; then
    awk 'BEGIN{p=0}
    {
      print
      if (!p && $0 ~ /plugins\s*\{/) {
        print "    id(\"com.meta.spatial.plugin\") version \"0.8.0\""
        p=1
      }
    }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
  else
    # Groovy DSL
    awk 'BEGIN{p=0}
    {
      print
      if (!p && $0 ~ /plugins\s*\{/) {
        print "    id \"com.meta.spatial.plugin\" version \"0.8.0\""
        p=1
      }
    }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
  fi
fi

# 5) Adicionar dependências do Spatial SDK (se não tiver)
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

# 6) Criar flavor 'spatial' (se o módulo NÃO tem flavors ainda)
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
  # Já existem flavors: só alerta se não houver o 'spatial'
  if ! grep -q 'create("spatial")' "$APP_GRADLE"; then
    echo "AVISO: productFlavors já existem mas sem 'spatial'. Se o build falhar, edite o bloco de flavors e adicione create(\"spatial\")."
  fi
fi

# 7) Criar arquivos do flavor 'spatial': Manifest + ids + Activity
SPATIAL_DIR="$APP_DIR/src/spatial"
mkdir -p "$SPATIAL_DIR/res/values" "$SPATIAL_DIR/java/com/ichi2/anki/spatial"

# 7.1) Manifest (overlay do flavor)
cat > "$SPATIAL_DIR/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools"
          package="com.ichi2.anki">
  <application>
    <!-- Suporte explícito a Quest 2/3/3S -->
    <meta-data
      android:name="com.oculus.supportedDevices"
      android:value="quest2|quest3|quest3s" />

    <!-- Activity imersiva que registra/spawna os painéis 2D -->
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

    <!-- Permite embutir as Activities existentes -->
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

# 7.2) ids.xml (registrations)
cat > "$SPATIAL_DIR/res/values/ids.xml" <<'EOF'
<resources>
  <item name="panel_decks" type="id"/>
  <item name="panel_review" type="id"/>
</resources>
EOF

# 7.3) Activity (registra e "spawna" os paineis 2D)
cat > "$SPATIAL_DIR/java/com/ichi2/anki/spatial/AnkiSpatialActivity.kt" <<'EOF'
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

# 8) Build da variant 'spatialDebug' do MÓDULO DETECTADO
cd "$ANKI_DIR"
./gradlew --no-daemon "$APP_MODULE:assembleSpatialDebug"

# 9) Copiar APK(s) para a saída do pipeline
mkdir -p "$ROOT/output-apk"
find "$ANKI_DIR" -type f -name "*.apk" -exec cp {} "$ROOT/output-apk/" \;
