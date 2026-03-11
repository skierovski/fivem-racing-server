### Poprawki + Czyszczenie Sezonu 1

**Poprawki:**
- Usunięto sprawdzanie terenu (hill/terrain DQ) z antycheata — powodowało losowe dyskwalifikacje, za trudne do prawidłowego wykrycia
- Słupy sygnalizacji świetlnej (prop_traffic_*) teraz niezniszczalne jak latarnie uliczne
- Naprawiono rematch NUI — ekran rematch nie blokuje już kolejnego meczu po powrocie do menu (czyszczenie timeoutów, hideAll przy carPick i countdown)
- Hydranty znikają po zniszczeniu (wykrywanie po modelu + health <= 0)

**Sezon 1 — czyszczenie samochodów:**
- Usunięto wszystkie samochody z tieru "custom" (PixaCars, GOM, testowe) z serwera i server.cfg
- Usunięto ~50 zasobów pojazdów z serwera produkcyjnego
- Katalog pojazdów (vehicle_catalog) budowany automatycznie z kodu przy starcie — ranked + PD
- Freeroam F1 i Benny's pokazują te same kategorie: BRONZE → BLACKLIST + POLICE
- Wszystkie samochody ranked i PD dostępne dla każdego gracza (bez blokady tierów)
- Kolor tieru POLICE zmieniony na niebieski (#4488ff)
- Usunięto blokadę tierów w garażu menu — wszystkie filtry odblokowane
