# Jak wysłać handling auta na serwer

## Struktura folderów

```
twoj-folder/
  push-handling.ps1
  bronze/
    futo.meta
    gb_cometcl.meta
    rh4.meta
    ballerc.meta
  silver/
    gb_cometclf.meta
    gb_retinueloz.meta
    gb_schrauber.meta
  gold/
    roxanne.meta
    buffaloh.meta
    jester5.meta
    sent6.meta
    gb_gresleystx.meta
  platinum/
    gb_argento7f.meta
    gb_solace.meta
    gb_sultanrsx.meta
    sentinel5.meta
  diamond/
    gb_tr3s.meta
    elegyrh5.meta
  blacklist/
    gsttoros1.meta
    gb_comets2r.meta
```

## Jak używać

### 1. Edytuj plik .meta auta które testujesz

Otwórz np. `bronze/futo.meta` w edytorze tekstu i zmień wartości.

### 2. Otwórz PowerShell w folderze ze skryptem

Kliknij prawym na folder -> "Otwórz w terminalu" albo wpisz `cd sciezka\do\folderu`

### 3. Wyślij handling jednego auta

```powershell
.\push-handling.ps1 -CarName futo
```

Przykłady:
```powershell
.\push-handling.ps1 -CarName futo
.\push-handling.ps1 -CarName gb_cometcl
.\push-handling.ps1 -CarName rh4
.\push-handling.ps1 -CarName roxanne
.\push-handling.ps1 -CarName gb_tr3s
```

### 4. Odśwież handling na serwerze

W grze wciśnij **F8** i wpisz:
```
/refresh handling
```

### 5. Zrespawnuj auto żeby zobaczyć zmiany

Usuń obecne auto i zrespawnuj nowe — nowy handling załaduje się automatycznie.

## Ważne zasady

- **Wysyłaj TYLKO auto które edytujesz** — inni testerzy mogą pracować nad innymi autami w tym samym czasie
- **Nie edytuj aut innych testerów** bez uzgodnienia
- **Po każdej zmianie** wyślij i odśwież na serwerze żeby przetestować
- Nazwa auta musi być **dokładnie taka sama** jak nazwa pliku bez `.meta` (np. `futo`, `gb_cometcl`, `rh4`)

## Tiery i prędkości

| Tier | Prędkość max | Auta |
|---|---|---|
| Bronze | 105 mph | futo, gb_cometcl, rh4, ballerc |
| Silver | 115 mph | gb_cometclf, gb_retinueloz, gb_schrauber |
| Gold | 125 mph | roxanne, buffaloh, jester5, sent6, gb_gresleystx |
| Platinum | 135 mph | gb_argento7f, gb_solace, gb_sultanrsx, sentinel5 |
| Diamond | 145 mph | gb_tr3s, elegyrh5 |
| Blacklist | 155 mph | gsttoros1, gb_comets2r |
