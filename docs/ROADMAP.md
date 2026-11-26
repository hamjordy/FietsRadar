# FietsRadar – ontwikkelplan

FietsRadar is een gratis Flutter-app voor Android met fietsgerichte navigatie en wegmeldingen. De publieke repository blijft de enige bron voor de app.

## Werkende basis – geïmplementeerd

- [x] Flutter-projectstructuur en Android CI
- [x] GPS-locatie, live positie op OpenStreetMap en GPS-snelheidsmeter
- [x] Nederlandse bestemmingen zoeken via Nominatim
- [x] Fietsroutes berekenen via BRouter
- [x] Routeprofielen: gebalanceerd, vlot doorfietsen en veiligere route
- [x] Route-instructies uit BRouter verwerken en in het Nederlands uitspreken
- [x] Instellingen voor gesproken navigatie en waarschuwingen voor actieve meldingen in de buurt, lokaal opgeslagen
- [x] Volgende manoeuvre en resterende route-informatie tonen
- [x] Routevoortgang volgen, GPS-uitschieters negeren en automatisch herberekenen na route-afwijking
- [x] Android-achtergrondnavigatie tijdens een bewust gestarte rit via een foreground location service
- [x] Favoriete en recente bestemmingen lokaal bewaren
- [x] GPS-ritregistratie tijdens actieve navigatie met filtering van onnauwkeurige fixes en onwaarschijnlijke sprongen
- [x] Lokale ritgeschiedenis met datum, bestemming, afgelegde afstand, ritduur, gemiddelde snelheid en topsnelheid (maximaal 100 ritten)
- [x] Wegmeldingen voor gevaar, werkzaamheden, obstakels, gladheid en ongevallen
- [x] Meldingen lokaal bewaren en optioneel live delen via Supabase Realtime
- [x] Verlopen gedeelde meldingen automatisch verbergen en server-side opruimen
- [x] GitHub Actions: Flutter-analyse, tests en debug-APK

## Volgende ontwikkelfasen

1. **Betrouwbaarheid en ritregistratie**
   - [x] Pauzeren en hervatten van een actieve rit; gepauzeerde tijd telt niet mee in de ritduur en GPS-afstand
   - [x] Herstel van een actieve navigatiesessie na procesbeëindiging: bestemming, routeprofiel, afgelegde afstand en pauzestatus worden lokaal hersteld; de route wordt opnieuw berekend vanaf de actuele GPS-positie
   - [x] Duidelijke aankomst-/rit-voltooidstatus; rit automatisch opslaan en achtergrond-GPS stoppen bij aankomst
   - Tests voor routevoortgang, GPS-afwijkingen, aankomst en achtergrondgedrag

2. **Betere wegmeldingen**
   - Meldingen bevestigen of als opgelost markeren
   - Meldingen betwisten en moderatie-/misbruikafhandeling
   - [x] Leeftijd en geldigheidsstatus van meldingen in de meldingenlijst tonen; lokale meldingen duidelijk onderscheiden van server-bevestigde gedeelde meldingen\n   - Betrouwbaarheid en bevestigingsstatus van meldingen op kaart en lijst
   - End-to-end testen met meerdere echte toestellen en een geconfigureerd Supabase-project

3. **Verkeers- en fietsveiligheidsinformatie**
   - Betrouwbare bronnen voor wegafsluitingen en werkzaamheden onderzoeken
   - Fietspadstatus, gevaarlijke kruisingen en relevante waarschuwingen toevoegen waar data en licenties dit toestaan
   - Geen niet-geverifieerde of verouderde waarschuwingen als actuele feiten presenteren

4. **Productiegeschiktheid**
   - Geschikte kaart- en routeringsinfrastructuur kiezen op basis van licentie, kosten en gebruikslimieten
   - Caching, foutafhandeling, monitoring en privacy-instellingen
   - Toegankelijkheid, batterijverbruik en GPS-nauwkeurigheid verbeteren

5. **Uitgifte**
   - Testen op meerdere echte Android-versies en toestellen
   - Release signing en veilige sleutelopslag instellen
   - Privacyverklaring, store-vermelding en Google Play-release voorbereiden

## Grenzen en afhankelijkheden

- De Android-foregroundservice is in de code aanwezig, maar moet op echte telefoons en verschillende Android-versies worden getest. Android-fabrikanten kunnen achtergrondprocessen beperken.
- Live meldingen werken pas nadat een Supabase-project is ingesteld, de SQL-migratie is uitgevoerd, anonieme aanmelding is ingeschakeld en de twee GitHub Actions secrets zijn toegevoegd.
- Zonder Supabase-configuratie blijven meldingen lokaal; de navigatie blijft bruikbaar.
- OpenStreetMap-tegels, Nominatim en de publieke BRouter-server zijn ontwikkel-/startdiensten met voorwaarden en capaciteitslimieten. Gratis gebruik is geen garantie op onbeperkte productiecapaciteit.
- Een groene GitHub Actions-build bevestigt analyse, tests en debug-APK-build; dit is geen vervanging voor praktijktests op echte telefoons of een ondertekende release-build.
