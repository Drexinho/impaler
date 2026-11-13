# Impaler

Minimalistická aplikace do menu baru macOS (14+), která připne jedno cizí okno „vždy navrchu“. Skutečné okno zůstává, kde je; když ztratí fokus, překryje ho plovoucí živé zrcadlo (ScreenCaptureKit).

## Sestavení

```sh
./build.sh        # swift build -c release → Impaler.app (ad-hoc podpis)
open Impaler.app
```

Stačí Command Line Tools, žádné závislosti.

## Použití

- Ikona špendlíku v menu baru → **Připnout okno** → najeď na okno (modrý rámeček) a klikni. Esc výběr zruší.
- Připnuté okno má v pravém horním rohu odznak 📌; klik na něj (nebo **Odepnout** v menu) okno odepne.
- Klik do zrcadla aktivuje skutečné okno a klik do něj předá.

## Oprávnění

Při prvním spuštění je potřeba povolit **Zpřístupnění** a **Nahrávání obrazovky** (Nastavení systému → Soukromí a zabezpečení) a aplikaci spustit znovu. Podpis je ad-hoc, takže po každém novém sestavení může systém chtít oprávnění udělit znovu.

## Omezení

- Jen jedno připnuté okno.
- Zrcadlo předává jen kliknutí levým tlačítkem; tažení, pravý klik a rolování nad zrcadlem ne.
