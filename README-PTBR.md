# Anki Quest Spatial - CI

Este repositório permite **gerar um APK** do Anki com painel 2D ancorável no Meta Quest **sem mexer no seu Mac**: a compilação roda no **GitHub Actions** e você baixa o **APK** pronto.

## Passos (1ª vez)
1. Crie um repositório no seu GitHub (vazio).
2. Faça upload de **tudo deste ZIP** (inclusive a pasta `.github`).
3. No GitHub, vá em **Actions ▸ Build Anki Spatial APK ▸ Run workflow**.
4. Aguarde a execução terminar com **✔** e entre no passo **Artifacts** (lado direito).
5. Baixe o arquivo **anki-spatial-apk** (ZIP) — dentro tem o **APK** pronto para *sideload* no Quest.

## O que o workflow faz
- Baixa o código oficial do **AnkiDroid** (branch `stable`).
- Copia o nosso módulo `spatial-shell` para dentro do projeto.
- Ajusta o Gradle para criar o flavor **`spatial`** e incluir o **Meta Spatial SDK**.
- Compila o **`assembleSpatialDebug`**.
- Publica os APKs em **Artifacts**.

> Uso pessoal (sideload): ok. Se quiser **distribuir** o APK, publique também o **código-fonte** correspondente (GPLv3).

## Depois de baixar o APK
Instale no Quest via **Meta Quest Developer Hub** (Install APK) ou **SideQuest**.

## Ajuda
Se o job falhar, copie a **mensagem de erro** e me envie.
