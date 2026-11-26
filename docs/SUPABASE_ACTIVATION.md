# FietsRadar – live meldingen activeren

De Supabase-migratie en anonieme aanmelding zijn ingesteld in het Supabase-project. De GitHub Actions repository secrets moeten exact deze namen hebben:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

De Android-workflow geeft deze secrets als compile-time `--dart-define` waarden door aan Flutter. Een nieuwe build na het toevoegen van de secrets is noodzakelijk; een eerder gebouwde APK bevat de nieuwe configuratie niet.

## Controle na de build

1. Open de nieuwste geslaagde **Android build** onder GitHub Actions.
2. Download `fietsradar-android-debug` onder Artifacts.
3. Installeer de APK op Android en open FietsRadar.
4. Open **Meldingen**. De status moet **Live meldingen actief** worden.
5. Plaats eventueel een testmelding en controleer of deze in de `road_reports` tabel in Supabase verschijnt.
6. Test pas daarna met een tweede toestel of tweede app-installatie of meldingen live binnenkomen.

Gebruik uitsluitend de Supabase publishable key. Zet nooit een Supabase secret/service-role key in de app of in de build-secrets.

Als de status niet actief wordt, controleer dan eerst of de twee repository secrets exact gespeld zijn en of de SQL-migratie volledig is uitgevoerd.
