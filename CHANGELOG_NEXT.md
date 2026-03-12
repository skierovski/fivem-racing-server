## Co nowego

### Naprawa pościgów (Chase)
- **Łapanie runnera** — naprawiono bug, gdzie timer łapania resetował się gdy dalsi policjanci raportowali dystans. Teraz timer działa poprawnie niezależnie od liczby ścigających
- **Timer ucieczki i boxingu** — przejście na śledzenie czasu rzeczywistego zamiast inkrementacji per-raport, eliminuje skalowanie z liczbą graczy
- **PIT przy niskiej prędkości (boxing)** — kontakty poniżej 30 km/h po obu stronach nie są już karane jako PIT (dotyczy chase i ranked)
- **Friendly fire przy boxingu** — kontakt PD-PD w promieniu 25m od runnera nie jest już karany (naturalne zderzenia przy boxowaniu)
- **Broń na Code Red** — naprawiono brak broni mimo widocznego HUD-a. Teraz asset broni jest poprawnie ładowany i automatycznie wybierany
- **Garaż Benny's: SUV-y wbijające się w podłogę** — po załadowaniu tuningu (zawieszenie zmienia wysokość) pojazd jest ponownie ustawiany na podłodze
- **Garaż Benny's: UI się nie ładuje** — dodano timeout 5s na dane tuningu z serwera, jeśli nie przyjdą UI otworzy się z pustym tuningiem
