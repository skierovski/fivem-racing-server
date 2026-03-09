### Poprawki: Chase & Ranked - Batch 3
- Ekran zwycięstwa/porażki automatycznie znika po 20s w ranked (zabezpieczenie jeśli returnToMenu nie dotrze)
- Propsy niszczalne (kosze, pachołki itp.) znikają tylko przy faktycznej kolizji, nie przy samej bliskości
- Latarnie uliczne wzmocnione: SetEntityInvincible + FreezeEntityPosition + SetDisableFragDamage
- NPC zwalniają płynnie (stopniowe obniżanie prędkości co sekundę zamiast nagłego ucięcia silnika)
- NPC reagują tylko gdy ścigający ma włączone syreny (Q/Alt), runner nie wywołuje reakcji ruchu
- Cooldown 5s na kary PIT dla ścigających (zapobiega podwójnym karom z jednego zderzenia)
- Nadużycie terenu wyłączone w trybie chase (działa tylko w ranked)
- Poprawka winy kolizji: PD taranujący runnera od tyłu nie podnosi kodu policyjnego (sprawdzanie prędkości obu pojazdów)
