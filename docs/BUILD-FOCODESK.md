# Build do FocoDesk — o que buildamos e por quê

Este fork é mantido pela Foco Sistemas. **Hoje só distribuímos a versão Windows (x86_64).**
Android e macOS ficam para o futuro, se/quando houver demanda real. Este documento
registra o que está **ligado** e **desligado** na CI e como reverter.

## O que está LIGADO (build atual)

Ao rodar o workflow **Flutter Nightly Build** (`flutter-nightly.yml` → `flutter-build.yml`):

| Job | Para quê |
|-----|----------|
| `validate-update-metadata-keys` | validação rápida (ubuntu) |
| `generate-bridge` | ponte Rust↔Dart, necessária pelo Windows (ubuntu, barato) |
| `build-RustDeskTempTopMostWindow` | helper nativo do Windows |
| `build-for-windows-flutter` (**x86_64**) | **o cliente FocoDesk** + instalador (`focodesk-installer-x86_64`) |

Artefato que usamos: **`focodesk-installer-x86_64`** (contém `FocoDesk-x86_64.exe` + `.msi`).

## O que está DESLIGADO (e por quê)

| Job / alvo | Estado | Motivo |
|------------|--------|--------|
| `build-rustdesk-android` | `if: false` | Hoje não distribuímos Android |
| `build-rustdesk-android-universal` | `if: false` | idem |
| `build-for-windows-sciter` | `if: false` | UI Sciter legada; usamos só o cliente Flutter |
| Windows ARM (`aarch64`) no `build-for-windows-flutter` | bloco comentado | Parque é x86_64 (PDVs/PCs) |
| macOS, iOS, Linux, web, appimage, flatpak | `if: false` (já vinham desligados) | Fora de escopo hoje |

### Por que isso NÃO é sobre custo de minutos

O repositório `fsRepository/focodesk` é **público**, e GitHub Actions em repo público é
**gratuito e ilimitado** (inclusive macOS/Android). Desligar esses jobs serve para:
- **velocidade** — o build termina sem esperar plataformas que não usamos;
- **clareza** — a lista de artefatos mostra só o que realmente distribuímos;
- **blindagem** — se um dia o repo virar privado, já está enxuto (aí sim minutos custam:
  Linux 1x, Windows 2x, macOS 10x).

O custo de Actions na conta vem dos **repositórios privados**, não deste.

## Como reativar algo

- **Android**: nos jobs `build-rustdesk-android` e `build-rustdesk-android-universal`,
  troque `if: false` por `if: ${{ inputs.upload-artifact }}` (universal) e remova o `if: false` (apk).
- **Windows ARM (aarch64)**: descomente o bloco `aarch64-pc-windows-msvc` na matriz de
  `build-for-windows-flutter`.
- **Sciter / macOS / Linux / etc.**: remova o `if: false` do job correspondente.

Depois de qualquer mudança, rode o **CI Lint** (actionlint + focodesk-verify) — ele valida
os workflows e as âncoras FocoDesk antes de um build longo.
