# FietsRadar 🚲

**Gratis fiets-navigatie voor Android.** FietsRadar wordt gebouwd als een overzichtelijke fietsvariant van de bekende navigatie- en verkeersmeldingsapps: met GPS, fietsroutebegeleiding, snelheid en meldingen onderweg.

> Deze repository bevat de eerste werkende projectbasis (0.1.0). De app is nog in ontwikkeling en is nog niet klaar voor publicatie in Google Play.

## Wat zit er in deze eerste versie?

- **GPS-locatie:** vraagt Android-locatietoestemming en toont de actuele positie op de kaart.
- **Snelheidsmeter:** toont de actuele GPS-snelheid in km/u zolang de app open is.
- **Bestemming zoeken:** zoekt Nederlandse adressen en plaatsen.
- **Fietsroute:** vraagt een fietsroute op via het BRouter-profiel `trekking` en tekent die op de kaart.
- **Gesproken route-instructies:** BRouter levert afslagaanwijzingen zoals linksaf, rechtsaf en rotondes; FietsRadar kondigt de volgende manoeuvre in het Nederlands aan.
- **Routebewaking:** negeert onnauwkeurige GPS-fixes, controleert of je op de route fietst en berekent automatisch een nieuwe route wanneer je twee opeenvolgende GPS-updates duidelijk van de route af zitten.
- **Wegmeldingen:** meldingen voor gevaar, wegwerkzaamheden, obstakels, gladheid en ongevallen. In deze eerste versie worden ze alleen in het geheugen van de geopende app bijgehouden.
- **Android CI:** GitHub Actions voert code-analyse en tests uit en bouwt een debug-APK.

## Technologie

- Flutter / Dart
- `geolocator` voor Android GPS
- `flutter_map` en OpenStreetMap voor de kaartweergave
- Nominatim voor het zoeken van bestemmingen
- BRouter voor fietsrouteberekening
- `flutter_tts` voor Nederlandse gesproken meldingen

## Zelf bouwen en starten

Installeer eerst de Flutter SDK en Android Studio / Android SDK. Voer daarna vanuit de repositorymap uit:

```bash
flutter pub get
bash tool/bootstrap_android.sh
flutter run
```

De eerste start vraagt toestemming voor locatie. Zet GPS aan en geef FietsRadar toestemming. Zoek daarna een bestemming en tik op een resultaat om een fietsroute te berekenen.

### APK downloaden via GitHub Actions

Na een push naar `main` voert de workflow **Android build** de analyse, tests en debug-build uit. Als de workflow slaagt, staat de APK bij de workflowrun onder **Artifacts** als `fietsradar-android-debug`.

## Gratis diensten en gebruikslimieten

De code gebruikt op dit moment publieke diensten om zonder API-sleutel te kunnen starten. Dat maakt deze ontwikkelfase goedkoop, maar is geen garantie voor onbeperkt productiegebruik:

- **OpenStreetMap-kaarttegels:** de app toont zichtbare kaarttegels en vermeldt © OpenStreetMap contributors. De publieke OSM-tegelservers zijn best-effort, hebben geen SLA en mogen niet worden gebruikt voor bulkdownloads of offline kaartpakketten. Voor een grotere uitrol moet een geschikte kaartprovider of eigen tile-infrastructuur worden gekozen. Zie de [officiële tile policy](https://operations.osmfoundation.org/policies/tiles/).
- **Nominatim:** de zoekfunctie houdt minimaal ongeveer één seconde tussen opeenvolgende zoekopdrachten aan en identificeert de app met een User-Agent. De publieke zoekdienst is niet bedoeld als onbeperkte commerciële geocoder.
- **BRouter:** de publieke router wordt gebruikt voor de eerste fietsrouteberekeningen. Voor structureel of grootschalig gebruik is een eigen of gecontracteerde routeringsdienst verstandig.

## Wat werkt nog niet / volgende stappen

Dit is nadrukkelijk nog geen volledige vervanger van Waze of Flitsmeister. De basis is gelegd; voor een betrouwbare publieke app moeten onder andere deze onderdelen nog worden gebouwd en getest:

1. Achtergrondnavigatie met een Android foreground service en blijvende navigatiemelding.
3. Een online meldingenbackend zodat meldingen van andere fietsers binnenkomen, inclusief moderatie en automatische vervaltijd.
4. Actuele wegafsluitingen, fietspadstatus, gevaarlijke punten en drukte uit betrouwbare databronnen.
5. Favoriete bestemmingen, recente routes, routevoorkeuren en privacy-instellingen.
6. Productiegeschikte kaart- en routeringsinfrastructuur, licentiecontrole, caching en monitoring.
7. Uitgebreide tests op echte Android-telefoons, batterijverbruik en GPS-nauwkeurigheid.
8. Ondertekende release-build en voorbereiding voor publicatie in Google Play.

De huidige GPS-tracking werkt zolang de app op de voorgrond actief is. Meldingen worden nog niet naar een server gestuurd. De eerste gesproken afslagbegeleiding en automatische herberekening zijn toegevoegd. Achtergrondnavigatie met scherm uit en uitgebreide praktijktests volgen nog.

## Privacy in deze prototypeversie

FietsRadar heeft nog geen account of eigen backend. De GPS-positie wordt op het toestel gebruikt om de kaart bij te houden en wordt samen met de gekozen bestemming naar BRouter gestuurd wanneer een route wordt berekend. De ingevoerde bestemming wordt naar Nominatim gestuurd bij het zoeken. Kaartverzoeken gaan naar de ingestelde kaarttegelprovider. Meldingen blijven lokaal in het geheugen van de geopende app en worden niet gedeeld.

