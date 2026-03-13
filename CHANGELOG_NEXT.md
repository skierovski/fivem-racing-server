## Co nowego

### Menu — nowy design z pod-stronami trybów
- **Pod-strony trybów** — kliknięcie Ranked lub Chase otwiera dedykowaną stronę trybu z przyciskiem kolejki, opcjami, informacjami o trybie, ostatnimi meczami i tabelą liderów
- **Przycisk powrotu** — strzałka w lewo wraca do wyboru trybu, ESC również działa
- **Ostatnie mecze** — pod-strona wyświetla 10 ostatnich meczów gracza w danym trybie (przeciwnik, wynik, zmiana MMR, czas trwania)
- **Tabela liderów** — top 10 graczy w danym trybie
- **Solo Test** — przeniesiony do rozwijalnej sekcji wewnątrz każdego trybu (nie osobna karta)
- **Opcje Ranked** — Cross-Tier i Test Ranked toggle przeniesione do pod-strony Ranked

### Naprawy pościgów (Chase)
- **Detekcja PIT-ów** — dodano śledzenie szczytowego kąta skrętu z ostatnich 1.5s (chaser puszczał kierownicę w momencie kontaktu, co dawało steer=0° i score=1). Teraz system używa peak steering zamiast chwilowego kąta
- **Bonus za typ PIT_MANEUVER** — kontakt z boku pod podobnym kątem (+1 do score) — wcześniej tylko REAR_END dawał bonus
- **Broń na Code Red** — broń jest teraz dawana na starcie meczu (w inventory), a weapon wheel odblokowany dopiero na Code Red. Eliminuje problem z dawaniem broni w samochodzie
- **Runner ram PD** — naprawiono detekcję ramowania PD przez runnera. Usunięto filtr heading < 90° (blokował PIT-y z tyłu), zastąpiono sprawdzaniem yaw rate (> 45°/s = spin po PITcie, nie celowe ramowanie)
- **Kolejkowanie z freeroam** — gracze w trybie freeroam mogą teraz normalnie dołączyć do kolejki (wcześniej blokowane przez stan 'freeroam' != 'menu')

### Garaż Benny's
- **Zamykanie UI przy kolejce** — gdy gracz jest w garażu i zostanie wciągnięty do meczu, UI garażu poprawnie się zamyka
