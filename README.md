# FietsRadar 🚲

**Gratis fiets-navigatie voor Android.** FietsRadar wordt gebouwd als een overzichtelijke fietsvariant van de bekende navigatie- en verkeersmeldingsapps: met GPS, fietsroutebegeleiding, snelheid en meldingen onderweg.

> Deze repository bevat de eerste werkende projectbasis (0.4.0). De app is nog in ontwikkeling en is nog niet klaar voor publicatie in Google Play.

## Wat zit er in deze eerste versie?

- **GPS-locatie:** vraagt Android-locatietoestemming en toont de actuele positie op de kaart.
- **Snelheidsmeter:** toont de actuele GPS-snelheid in km/u.
- **Achtergrondnavigatie (Android):** tijdens een zelf gestarte navigatierit gebruikt FietsRadar een locatie-voorgrondservice met een blijvende Android-melding, zodat GPS-updates doorgaan wanneer het scherm uitstaat of je een andere app opent. De service stopt wanneer je de navigatie stopt.
- **Bestemming zoeken:** zoekt Nederlandse adressen en plaatsen.
- **Fietsroute:** vraagt een fietsroute op via het BRouter-profiel `trekking` en tekent die op de kaart.
- **Gesproken route-instructies:** BRouter levert afslagaanwijzingen zoals linksaf, rechtsaf en rotondes; FietsRadar kondigt de volgende manoeuvre in het Nederlands aan.
- **Routebewaking:** negeert onnauwkeurige GPS-fixes, controleert of je op de route fietst en berekent automatisch een nieuwe route wanneer je twee opeenvolgende GPS-updates duidelijk van de route af zitten.
- **Wegmeldingen:** gevaar, wegwerkzaamheden, obstakels, gladheid en ongevallen worden lokaal bewaard. Na het instellen van Supabase worden meldingen ook live gedeeld met andere fietsers, met automatische vervaltijden en basisbeveiliging tegen spam.
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

### Live meldingen instellen (Supabase)

De gedeelde meldingen gebruiken Supabase. De app blijft ook zonder Supabase volledig bruikbaar; in dat geval blijven meldingen alleen op dit toestel.

1. Maak een gratis project aan via [Supabase](https://database.new).
2. Open **Authentication → Sign In / Providers** en schakel **Anonymous Sign-Ins** in.
3. Open de SQL Editor en voer het bestand `supabase/migrations/20261126070000_shared_road_reports.sql` volledig uit.
4. Kopieer in **Project Settings → API Keys** de Project URL en de **publishable key** (deze begint bij nieuwe projecten met `sb_publishable_`).
5. Voeg in GitHub bij **Settings → Secrets and variables → Actions** twee repository secrets toe:
   - `SUPABASE_URL`: de Project URL
   - `SUPABASE_PUBLISHABLE_KEY`: de publishable key

Gebruik nooit een Supabase secret key of service-role key in de app of GitHub Actions build. De database gebruikt Row Level Security; clients lezen alleen actieve meldingen, kunnen eigen meldingen publiceren en alleen hun eigen meldingen verwijderen. Publicaties krijgen een server-side vervaltijd; een geplande database-taak verwijdert verlopen meldingen elke tien minuten. De server controleert ook een basislimiet per gebruiker.

Om lokaal met live meldingen te bouwen:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Zonder beide instellingen start de app automatisch in de lokale modus. De Supabase Free-plan is geschikt om te beginnen en te testen, maar heeft gebruikslimieten en kan projecten na een week inactiviteit pauzeren. Houd de actuele limieten in de gaten voordat de app publiek groeit.

### APK downloaden via GitHub Actions

Na een push naar `main` voert de workflow **Android build** de analyse, tests en debug-build uit. Als de workflow slaagt, staat de APK bij de workflowrun onder **Artifacts** als `fietsradar-android-debug`.

## Gratis diensten en gebruikslimieten

De code gebruikt op dit moment publieke diensten om zonder API-sleutel te kunnen starten. Dat maakt deze ontwikkelfase goedkoop, maar is geen garantie voor onbeperkt productiegebruik:

- **OpenStreetMap-kaarttegels:** de app toont zichtbare kaarttegels en vermeldt © OpenStreetMap contributors. De publieke OSM-tegelservers zijn best-effort, hebben geen SLA en mogen niet worden gebruikt voor bulkdownloads of offline kaartpakketten. Voor een grotere uitrol moet een geschikte kaartprovider of eigen tile-infrastructuur worden gekozen. Zie de [officiële tile policy](https://operations.osmfoundation.org/policies/tiles/).
- **Nominatim:** de zoekfunctie houdt minimaal ongeveer één seconde tussen opeenvolgende zoekopdrachten aan en identificeert de app met een User-Agent. De publieke zoekdienst is niet bedoeld als onbeperkte commerciële geocoder.
- **BRouter:** de publieke router wordt gebruikt voor de eerste fietsrouteberekeningen. Voor structureel of grootschalig gebruik is een eigen of gecontracteerde routeringsdienst verstandig.

## Wat werkt nog niet / volgende stappen

Dit is nadrukkelijk nog geen volledige vervanger van Waze of Flitsmeister. De basis is gelegd; voor een betrouwbare publieke app moeten onder andere deze onderdelen nog worden gebouwd en getest:

1. Supabase-project configureren en gedeelde meldingen op meerdere echte telefoons end-to-end testen.
2. Uitgebreidere moderatie, meldingen bevestigen / betwisten en sterkere bescherming tegen misbruik toevoegen.
3. Actuele wegafsluitingen, fietspadstatus, gevaarlijke punten en drukte uit betrouwbare databronnen.
4. Favoriete bestemmingen, recente routes, routevoorkeuren en privacy-instellingen.
5. Productiegeschikte kaart- en routeringsinfrastructuur, licentiecontrole, caching en monitoring.
6. Uitgebreide tests op echte Android-telefoons, batterijverbruik en GPS-nauwkeurigheid.
7. Ondertekende release-build en voorbereiding voor publicatie in Google Play.

De Android GPS-voorgrondservice is toegevoegd voor actieve navigatieritten. Deze functie moet nog op echte telefoons en verschillende Android-versies worden getest, inclusief batterijbesparing en het intrekken van locatietoestemming. De Supabase-client en database-migratie voor live meldingen staan in de repository, maar live delen wordt pas actief nadat een Supabase-project is aangemaakt, de SQL-migratie is uitgevoerd en de twee GitHub Actions secrets zijn ingesteld. De eerste gesproken afslagbegeleiding en automatische herberekening zijn toegevoegd.

## Privacy in deze prototypeversie

FietsRadar vereist geen e-mailadres of wachtwoord voor live meldingen: na configuratie maakt Supabase een anoniem app-account aan. Alleen wanneer een gebruiker zelf een wegmelding plaatst, worden het gekozen meldingstype en de actuele GPS-coördinaten naar de gedeelde backend gestuurd en zichtbaar voor andere FietsRadar-gebruikers. Deze meldingen verlopen na 2 tot 24 uur. De app deelt de doorlopende GPS-beweging niet met andere gebruikers. Zonder backendconfiguratie blijven meldingen alleen lokaal. De GPS-positie wordt op het toestel gebruikt om de kaart bij te houden en wordt samen met de gekozen bestemming naar BRouter gestuurd wanneer een route wordt berekend. De ingevoerde bestemming wordt naar Nominatim gestuurd bij het zoeken. Kaartverzoeken gaan naar de ingestelde kaarttegelprovider.

