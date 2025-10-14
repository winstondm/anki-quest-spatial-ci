#!/usr/bin/env bash
set -euxo pipefail

# Caminhos
ROOT="$GITHUB_WORKSPACE"
ANKI_DIR="$ROOT/Anki-Android"

# 1) Clonar AnkiDroid (branch estável)
git clone --depth=1 --branch stable https://github.com/ankidroid/Anki-Android.git "$ANKI_DIR"

# 2) Copiar nosso módulo spatial-shell para dentro do projeto do AnkiDroid
cp -r "$ROOT/spatial-shell" "$ANKI_DIR/spatial-shell"

# 3) Incluir o módulo no settings.gradle(.kts)
if [ -f "$ANKI_DIR/settings.gradle.kts" ]; then
  echo 'include(":spatial-shell")' >> "$ANKI_DIR/settings.gradle.kts"
else
  echo 'include(":spatial-shell")' >> "$ANKI_DIR/settings.gradle"
fi

APP_GRADLE="$ANKI_DIR/AnkiDroid/build.gradle.kts"
if [ ! -f "$APP_GRADLE" ]; then
  # fallback: alguns forks nomeiam :app
  APP_GRADLE="$ANKI_DIR/app/build.gradle.kts"
fi

# 4) Adicionar plugin do Spatial SDK no módulo do app
if ! grep -q 'com.meta.spatial.plugin' "$APP_GRADLE"; then
  awk 'BEGIN{added=0}
  { print; if(!added && $0 ~ /plugins\s*\{/) { print "    id(\"com.meta.spatial.plugin\") version \"0.8.0\""; added=1 } }'     "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

# 5) Adicionar flavors mobile/spatial se não existem
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
fi

# 6) Adicionar dependências do Spatial SDK no módulo do app
if ! grep -q 'meta-spatial-sdk' "$APP_GRADLE"; then
  awk 'BEGIN{added=0}
  { print; if(!added && $0 ~ /dependencies\s*\{/) {
      print "    implementation(\"com.meta.spatial:meta-spatial-sdk:0.8.0\")"
      print "    implementation(\"com.meta.spatial:meta-spatial-sdk-toolkit:0.8.0\")"
      print "    implementation(\"com.meta.spatial:meta-spatial-sdk-vr:0.8.0\")"
      print "    implementation(\"com.meta.spatial:meta-spatial-sdk-physics:0.8.0\")"
      added=1
    }
  }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

# 7) Build Debug do flavor spatial
cd "$ANKI_DIR"
./gradlew --no-daemon :AnkiDroid:assembleSpatialDebug || ./gradlew --no-daemon :app:assembleSpatialDebug

# 8) Copiar APKs para uma pasta de saída
mkdir -p "$ROOT/output-apk"
find "$ANKI_DIR" -type f -name "*.apk" -exec cp {} "$ROOT/output-apk/" \;
