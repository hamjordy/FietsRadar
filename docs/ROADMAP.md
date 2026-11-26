# FietsRadar – ontwikkelplan

## Eerste basisversie
- [x] Flutter-projectstructuur voor Android
- [x] GPS-locatie en live positie op de kaart zolang de app geopend is
- [x] Snelheidsweergave op basis van GPS
- [x] Nederlandse bestemmingen zoeken
- [x] Fietsroute berekenen via het BRouter-fietsprofiel
- [x] Route op de kaart tekenen
- [x] Nederlandse gesproken start- en routewaarschuwing
- [x] Meldingen voor gevaar, wegwerkzaamheden, obstakels, gladheid en ongevallen (lokaal op toestel)
- [x] GitHub Actions-workflow voor tests en Android APK-build

## Volgende ontwikkelfasen
1. Betrouwbare turn-by-turn aanwijzingen en automatische herberekening na afwijken van de route.
2. Achtergrondnavigatie met een Android foreground service, blijvende notificatie en correcte Android-toestemmingen.
3. Online meldingenplatform zodat meldingen van andere fietsers zichtbaar worden, met moderatie, vervaltijd en bescherming tegen misbruik.
4. Verkeerslagen zoals wegafsluitingen, fietspadstatus, gevaarlijke kruisingen en drukte op basis van controleerbare databronnen.
5. Favoriete bestemmingen, recente zoekopdrachten, routevoorkeuren en toegankelijkheidsinstellingen.
6. Productiegeschikte kaart- en routeringsdiensten, caching volgens licentievoorwaarden, monitoring en privacy-instellingen.
7. Testen op echte Android-telefoons en uitbrengen van een ondertekende release-APK / Play Store-build.

## Belangrijke grenzen van de eerste versie
- GPS wordt gevolgd zolang FietsRadar actief op het scherm staat; navigatie in de achtergrond is nog niet geïmplementeerd.
- Een melding wordt alleen op het huidige toestel bewaard. Er is nog geen server die meldingen naar andere fietsers stuurt.
- De eerste versie gebruikt publieke OpenStreetMap-kaarttegels, Nominatim-zoekopdrachten en de publieke BRouter-router. Deze gratis publieke diensten hebben gebruiksvoorwaarden en beschikbaarheidslimieten; ze zijn geen gegarandeerde onbeperkte productie-infrastructuur.
- De huidige gesproken begeleiding kondigt de start en een route-afwijking/bestemming aan. Volledige gesproken afslag-voor-afslag begeleiding moet nog worden toegevoegd.
- Snelheid en geschatte reistijd zijn indicatief en afhankelijk van GPS-nauwkeurigheid, routekwaliteit en fietsomstandigheden.
