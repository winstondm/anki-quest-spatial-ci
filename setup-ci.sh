#!/usr/bin/env bash
set -euxo pipefail

ROOT="$GITHUB_WORKSPACE"
ANKI_DIR="$ROOT/Anki-Android"

# 1) Clonar AnkiDroid (branch principal)
git clone --depth=1 --branch main https://github.com/ankidroid/Anki-Android.git "$ANKI_DIR"

# 2) Copiar nosso módulo spatial-shell para dentro do projeto do AnkiDroid
cp -r "$ROOT/spatial-shell" "$ANKI_DIR/spatial-shell"

# 3) Descobrir settings.gradle(.kts) e garantir include com quebra de linha
if [ -f "$ANKI_DIR/settings.gradle.kts" ]; then
  SETTINGS="$ANKI_DIR/settings.gradle.kts"
else
  SETTINGS="$ANKI_DIR/settings.gradle"
fi

# Se colou "… )include(":spatial-shell")" sem quebra de linha, conserta
sed -i 's/)\s*include(":spatial-shell")/)\ninclude(":spatial-shell")/g' "$SETTINGS"
# Se ainda não tem o include, adiciona com quebra de linha
if ! grep -q 'include(":spatial-shell")' "$SETTINGS"; then
  printf '\ninclude(":spatial-shell")\n' >> "$SETTINGS"
fi

# 4) Achar o módulo de app (aquele que tem com.android.application)
APP_GRADLE="$(grep -rl --include=build.gradle --include=build.gradle.kts 'id\s*[(]"\?com\.android\.application"\?' "$ANKI_DIR" | head -n1)"
if [ -z "$APP_GRADLE" ]; then
  echo "ERRO: não achei build.gradle(.kts) com 'com.android.application'"; exit 1
fi
APP_MODULE_DIR="$(dirname "$APP_GRADLE")"
APP_MODULE_NAME="$(basename "$APP_MODULE_DIR")"

echo "Módulo de app detectado: :$APP_MODULE_NAME ($APP_GRADLE)"

# 5) Ajustar o spatial-shell para depender do módulo de app correto
# (por padrão o arquivo usa :AnkiDroid; trocamos para o detectado)
sed -i "s/project(\":AnkiDroid\")/project(\":$APP_MODULE_NAME\")/g" "$ANKI_DIR/spatial-shell/build.gradle.kts"

# 6) Remover ícone do Manifest do spatial-shell (evita erro de recurso ausente)
sed -i '/android:icon=/d' "$ANKI_DIR/spatial-shell/src/main/AndroidManifest.xml"

# 7) Injetar plugin do Spatial SDK no módulo do app (se não existir)
if ! grep -q 'com.meta.spatial.plugin' "$APP_GRADLE"; then
  awk 'BEGIN{p=0}
  {
    print
    if (!p && $0 ~ /plugins\s*\{/) { print "    id(\"com.meta.spatial.plugin\") version \"0.8.0\""; p=1 }
  }' "$APP_GRADLE" > "$APP_GRADLE.tmp" && mv "$APP_GRADLE.tmp" "$APP_GRADLE"
fi

# 8) Garantir flavors; se não houver productFlavors, criamos mobile/spatial
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
  # Já existe bloco de flavors; garante que há o flavor spatial (super simples: só confere)
  if ! grep -q 'create("spatial")' "$APP_GRADLE"; then
    echo "ATENÇÃO: productFlavors já existem mas sem 'spatial'. Ajuste manual pode ser necessário."
  fi
fi

# 9) Adicionar dependências do Spatial SDK no módulo do app (se não existirem)
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

# 10) Build da variant spatialDebug do módulo detectado
cd "$ANKI_DIR"
./gradlew --no-daemon ":$APP_MODULE_NAME:assembleSpatialDebug"

# 11) Copiar APK(s) para a saída do pipeline
mkdir -p "$ROOT/output-apk"
find "$ANKI_DIR" -type f -name "*.apk" -exec cp {} "$ROOT/output-apk/" \;
