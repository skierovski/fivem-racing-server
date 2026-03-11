### Refaktoryzacja kodu + Tryb Solo Test

**Refaktoryzacja (czystość kodu, bez zmian w działaniu):**
- Nowy zasób `lib` — wspólne funkcje pomocnicze (getIdentifier, loadModelWithFallback, resolveGroundZ) wyciągnięte z 7 zasobów, eliminacja duplikacji kodu
- Ujednolicenie tuningu: garage deleguje do vehicles (jedno źródło prawdy)
- Chase client: 30+ magicznych liczb wyciągniętych do tabeli `CC`, nowe helpery (forEachOtherPlayer, forceFullVisibility, updateInputState, detectWaterContact, processAirborne, classifyTerrain, trackHillTime, detectBrakeCheck)
- Chase server: wyciągnięcie getActiveMatch (zastępuje 12+ powtórzeń), podział startChaseMatch na fazy (runCarPickPhase, runHeliVotePhase, runSpawnPhase, runCountdownPhase), nowe stałe w ChaseConfig
- Matchmaking: usunięcie martwego kodu (selectRunnerCar, selectPDCars, Kasyno), deduplikacja kolejek, stałe w Config
- Ranked: podział ProcessRankedResult na calculateMatchMMR, updatePlayerRankedData, notifyMatchResult
- Menu: deduplikacja closeMenu(), usunięcie pustego handlera w chat/client
- Naprawione globalne zmienne: chaseSirenState, freeroamPendingModel, networkTimer
- Znormalizowane wcięcia (4 spacje) i etykiety goto (::continue::) we wszystkich zasobach
- Spójne obsługiwanie błędów bazy danych (if not result then) w 9 callbackach oxmysql

**Nowa funkcja — Tryb Solo Test:**
- Nowy tryb "SOLO TEST" w menu (pomarańczowa karta z ikoną DEV)
- Możliwość wyboru trybu (Ranked / Chase) i roli (Runner / Chaser)
- Natychmiastowy start meczu bez kolejki — spawn na losowej lokacji z autem
- Naruszenia zasad wyłączone, brak zmian MMR, brak rematchów
- Forfeit/ESC czysto kończy sesję i wraca do menu
