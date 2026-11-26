# FietsRadar 🚲

**Gratis fiets-navigatie voor Android.** FietsRadar combineert GPS, fietsroutebegeleiding, snelheid en wegmeldingen in één app.

> FietsRadar is actief in ontwikkeling. Een geslaagde debug-build betekent nog niet dat de app klaar is voor publicatie in Google Play.

## Wat is al gebouwd?

- **GPS en snelheid:** actuele positie en snelheid op basis van GPS.
- **Kaart:** OpenStreetMap met de actuele positie.
- **Bestemming zoeken:** Nederlandse adressen en plaatsen via Nominatim.
- **Fietsroutes:** routeberekening via BRouter met drie profielen: gebalanceerd, vlot doorfietsen en veiligere route.
- **Gesproken navigatie:** Nederlandse afslagaanwijzingen op basis van BRouter voice hints.
- **Routebewaking:** voortgang, volgende manoeuvre en resterende route-informatie; onnauwkeurige GPS-fixes worden genegeerd en na herhaald afwijken wordt automatisch een nieuwe route berekend.
- **Achtergrondnavigatie:** tijdens een bewust gestarte navigatierit gebruikt Android een locatie-foregroundservice met blijvende melding.
- **Favorieten en recente bestemmingen:** lokaal opgeslagen op het toestel.
- **Wegmeldingen:** gevaar, wegwerkzaamheden, obstakels, gladheid en ongevallen.
- **Live meldingen (optioneel):** via Supabase Realtime; zonder backendconfiguratie blijven meldingen lokaal.
- **Android CI:** GitHub Actions voert Flutter-analyse en tests uit en bouwt een debug-APK.

## Technologie

- Flutter / Dart
- `geolocator` voor Android GPS en achtergrondlocatie tijdens navigatie
- `flutter_map` en OpenStreetMap voor kaartweergave
- Nominatim voor het zoeken van bestemmingen
- BRouter voor fietsrouteberekening en route-instructies
- `flutter_tts` voor Nederlandse gesproken begeleiding
- SharedPreferences voor lokale voorkeuren en bestemmingen
- Supabase voor optioneel gedeelde wegmeldingen

## Zelf bouwen en starten

Installeer Flutter SDK en Android Studio / Android SDK. Voer vanuit de repositorymap uit:

```bash
flutter pub get
bash tool/bootstrap_android.sh
flutter run
```

De eerste start vraagt locatietoestemming. Zet GPS aan, geef FietsRadar toestemming, zoek een bestemming en kies een resultaat om een fietsroute te berekenen.

## Live meldingen instellen (optioneel)

De app blijft bruikbaar zonder Supabase; meldingen worden dan alleen op dit toestel opgeslagen.

1. Maak een gratis project via [Supabase](https://database.new).
2. Schakel **Authentication → Sign In / Providers → Anonymous Sign-Ins** in.
3. Voer `supabase/migrations/20261126070000_shared_road_reports.sql` uit in de SQL Editor.
4. Kopieer de Project URL en de publishable key.
5. Voeg in GitHub bij **Settings → Secrets and variables → Actions** deze repository secrets toe:
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`

Gebruik nooit een Supabase secret key of service-role key in de app of GitHub Actions-build.

Lokaal bouwen met live meldingen:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## APK downloaden

Na een push naar `main` voert **Android build** de analyse, tests en debug-build uit. Bij een geslaagde workflowrun staat de APK onder **Artifacts** als `fietsradar-android-debug`.

Bekijk [GitHub Actions](https://github.com/hamjordy/FietsRadar/actions).

## Gratis diensten en gebruikslimieten

De app gebruikt publieke diensten om zonder API-sleutel te kunnen starten. Dit betekent niet dat ze onbeperkte productiecapaciteit bieden:

- **OpenStreetMap-kaarttegels:** publieke tegelservers zijn best-effort en hebben geen SLA. Bulkdownloads/offline pakketten zijn niet toegestaan op de publieke standaardserver. Zie de [tile usage policy](https://operations.osmfoundation.org/policies/tiles/).
- **Nominatim:** de zoekfunctie houdt minimaal ongeveer één seconde tussen opeenvolgende verzoeken aan. De publieke dienst is niet bedoeld als onbeperkte commerciële geocoder.
- **BRouter:** de publieke router wordt gebruikt voor routeberekeningen. Voor structureel of grootschalig gebruik is eigen of gecontracteerde infrastructuur nodig.
- **Supabase Free:** geschikt om te beginnen en te testen, maar kent gebruikslimieten en kan projecten na inactiviteit pauzeren.

## Wat volgt hierna?

De actuele ontwikkelvolgorde staat in [docs/ROADMAP.md](docs/ROADMAP.md). De belangrijkste volgende onderdelen zijn ritgeschiedenis en sessieherstel, bevestigen/betwisten van wegmeldingen, betrouwbare verkeersdata, praktijktests en voorbereiding van een ondertekende release.

## Privacy in deze versie

De app vereist geen account voor lokale navigatie. Na Supabase-configuratie wordt voor gedeelde meldingen een anoniem account aangemaakt. Alleen wanneer een gebruiker zelf een wegmelding plaatst, worden het gekozen meldingstype en de actuele GPS-coördinaten gedeeld met andere FietsRadar-gebruikers. De doorlopende GPS-beweging wordt niet met andere gebruikers gedeeld. Bestemmingszoekopdrachten gaan naar Nominatim en routeberekeningen sturen start- en eindcoördinaten naar BRouter.
