# Chunkowanie transkrypcji do korekty LM Studio — pod dowolny model

## Context

Korekta transkryptów spotkań przez LM Studio (`TranscriptCorrectionService`) już ma
mechanizm paczkowania (`batchParagraphs`, sentinele `⟦SEG:n⟧`/`⟦END⟧`, fallback do
raw), ale w praktyce **nie działa**: dzieli tekst wyłącznie po `\n`, a
`rawText` z Parakeeta to jeden ciągły string bez znaków nowej linii. Do tego
pojedynczy akapit dłuższy niż limit **nie jest w ogóle dzielony**
(`TranscriptCorrectionService.swift:105-114`). Efekt: całe spotkanie leci jako
jedna paczka → jedno żądanie → przepełnienie okna kontekstu przy mniejszych
modelach. Limit `maxCharsPerBatch = 4000` jest de facto martwy.

Dodatkowy fakt kluczowy dla „dowolny model": korekta to **proofreading** — model
przepisuje całą paczkę z powrotem, więc kontekst musi pomieścić **input +
output (~2×) + system prompt**. Rozmiar paczki musi to uwzględniać.

**Cel:** dowolnym modelem ogarnąć dowolnie długą transkrypcję. Rozwiązanie:
(1) naprawić cięcie tak, by długi ciągły tekst faktycznie był dzielony po
zdaniach; (2) automatycznie dobierać rozmiar paczki do okna kontekstu modelu
załadowanego w LM Studio (z fallbackiem i opcjonalnym ręcznym overridem).

## Decyzje (potwierdzone z użytkownikiem)

- **Rozmiar paczki:** auto-detekcja okna kontekstu z LM Studio; fallback do
  bezpiecznej wartości domyślnej; opcjonalny ręczny override w Settings.
- **Granice cięcia:** dzielenie długiego bloku po granicach zdań (`.!?`),
  potem po spacjach jako ostateczność — lokalnie w `TranscriptCorrectionService`,
  reużywając istniejących sentineli.

## Zmiany

### 1. `TranscriptCorrectionService.swift` — realne cięcie długich bloków

Plik: `CustomWhisper/Services/TranscriptCorrectionService.swift`

- Dodać pure funkcję `splitLongParagraph(_ text: String, maxChars: Int) -> [String]`:
  gdy `text.count > maxChars`, tnij po granicach zdań (skan po znakach, łam po
  `.`/`!`/`?` + spacja), a następnie **pakuj zdania zachłannie do bliskości
  `maxChars`** (kawałki bliskie limitowi, NIE per-zdanie — patrz inwersja pkt 5);
  jeśli pojedyncze „zdanie" nadal > `maxChars`, tnij po spacjach; ostatecznie
  twardo po znakach (żeby nigdy nie przekroczyć limitu — gwarancja „dowolna
  transkrypcja"). Cel: jak najmniej dużych fragmentów, nie dużo małych.
- W `batchParagraphs(_:maxChars:)` (linie 93-117): przed pakowaniem przepuścić
  każdy akapit przez `splitLongParagraph`, tak by żaden element wejściowy nie
  przekraczał `maxChars`. Reszta logiki (zachłanne grupowanie) bez zmian —
  sentinele i fallback działają dalej.

### 2. Auto-detekcja okna kontekstu z LM Studio

Plik: `CustomWhisper/Services/TranscriptCorrectionService.swift`

- `maxCharsPerBatch` w `init` zmienić na `Int?` (nil = „auto"). Domyślnie nil.
- Nowy request do natywnego REST API LM Studio (nie OpenAI-compat): z `baseURL`
  postaci `http://host:1234/v1` wyznaczyć root i uderzyć w
  `GET {root}/api/v0/models`. Zwraca m.in. `loaded_context_length` /
  `max_context_length` per model. Dodać:
  - `buildNativeModelsRequest() throws -> URLRequest` (analogicznie do
    `buildModelsRequest`, timeout ~10 s).
  - pure `static func parseContextLength(from data: Data, model: String) -> Int?`
    — znajdź wpis o `id == model` (i/lub `state == "loaded"`), zwróć
    `loaded_context_length` (preferowane — realne okno runtime). Gdy dostępne tylko
    `max_context_length`, użyj go z dodatkowym mnożnikiem bezpieczeństwa (np. ×0.5),
    bo max ≠ faktycznie załadowane okno (inwersja pkt 4). `nil` gdy brak.
  - `func detectContextTokens() async -> Int?` — wykonuje request; przy
    JAKIMKOLWIEK błędzie zwraca `nil` (auto-detekcja nigdy nie wywraca korekty).
- Pure `static func recommendedMaxChars(contextTokens: Int) -> Int` — wzór
  uwzględniający echo outputu (w tym blok reasoningu) i system prompt. Nazwane stałe
  (skorygowane inwersją):
  - `promptReserveTokens ≈ 500` (system prompt + narzut sentineli),
  - `echoFactor = 3.0` — output modelu reasoning (np. qwen3 `<think>`) bywa
    2–4× dłuższy niż input; dzielimy budżet z dużym zapasem na generację,
  - `charsPerToken ≈ 2.0` — **niski celowo** (polski tokenizuje się gęściej;
    niedoszacowanie znaków = przeszacowanie tokenów = bezpiecznie),
  - `safety = 0.85`, dolny floor (np. 800 znaków).
  - `chars = max(floor, Int(Double(context - reserve)/echoFactor * charsPerToken * safety))`.
- W `correct(_:progress:)` (linie 196-224) na starcie rozwiązać efektywny limit:
  `let limit = maxCharsPerBatch ?? recommendedMaxChars(detectContextTokens() ?? fallbackContextTokens)`.
  Fallback zakłada MAŁY kontekst z reasoningiem: `recommendedMaxChars(4096)` lub
  stała `AppConstants.Meeting.defaultCorrectionMaxChars` (patrz niżej — obniżona).
  Używać `limit` zamiast `maxCharsPerBatch` w `batchParagraphs`.
- **Izolacja błędów per-batch (inwersja pkt 3):** owinąć wnętrze pętli (request →
  validate → parse) w `do/catch`. Przy błędzie (np. HTTP 400 „context exceeded",
  timeout, zła odpowiedź) — `correctedParagraphs.append(contentsOf: batch)` (raw)
  i kontynuować kolejne paczki, zamiast rzucać wyjątek z całej funkcji.
  Dzięki temu jedna feralna paczka nie kasuje całej korekty. Zliczać liczbę
  paczek-fallbacków; jeśli WSZYSTKIE padły → rzuć oryginalny błąd (żeby UI
  pokazało „LM Studio nieosiągalne" zamiast cicho zwrócić raw).

### 3. Ręczny override + fallback w konfiguracji

Pliki: `CustomWhisper/Utilities/Constants.swift`, `CustomWhisper/Views/SettingsView.swift`,
`CustomWhisper/Core/MeetingTranscriber.swift`

- `Constants.swift`: dodać `AppConstants.Meeting.defaultCorrectionMaxChars`
  (obniżone do ~1800 — bezpieczne dla ~4k kontekstu Z reasoningiem, inwersja pkt 6)
  oraz `DefaultsKey.correctionMaxCharsOverride`.
- `SettingsView.swift` (sekcja „Local correction", ~192-241): dodać pole
  „Max characters per batch (blank = auto-detect)" powiązane `@AppStorage`.
  Puste/0 → auto; wartość > 0 → twardy override przekazany do serwisu.
  Krótki opis: „Auto uses the LM Studio model's context window."
- `MeetingTranscriber.correct(_:)` (linie 143-165): odczytać override z
  UserDefaults; przekazać do `TranscriptCorrectionService(baseURL:model:maxCharsPerBatch:)`
  (nil gdy auto). Reszta bez zmian.

### 4. `max_tokens` — świadomie NIE ustawiać

Ponieważ output ≈ input (przepisanie), a paczka jest teraz < kontekst/2,
zostawiamy `max_tokens` nieustawione (ustawienie ryzykowałoby ucięcie poprawnego
outputu). Odnotowane komentarzem przy `buildChatRequest`.

### 5. Testy

Plik: `CustomWhisperTests/TranscriptCorrectionServiceTests.swift`

- `splitLongParagraph`: długi string bez `\n` → wiele fragmentów, każdy ≤ limit;
  cięcie na granicach zdań; „zdanie" bez interpunkcji dłuższe niż limit →
  cięcie po spacjach/twarde; krótki tekst → bez zmian.
- `batchParagraphs`: newline-free transkrypt > limit → >1 paczka (regresja buga).
- `parseContextLength`: mock JSON natywnego `/api/v0/models` → poprawny
  `loaded_context_length`; brak modelu → nil; śmieciowy JSON → nil.
- `recommendedMaxChars`: rośnie z kontekstem, ≥ floor, sensowne wartości dla
  4096/8192.
- `detectContextTokens` z mock `HTTPClient`: sukces → liczba; błąd sieci/HTTP → nil.
- `correct` z mock klientem i auto-limitem: długi transkrypt → wiele żądań
  `/chat/completions`; sentinele/fallback nadal działają.
- **Izolacja per-batch (inwersja):** mock zwraca HTTP 400 dla jednej paczki,
  200 dla reszty → wynik kompletny, feralna paczka jako raw, funkcja NIE rzuca.
- **Wszystkie paczki padają** → `correct` rzuca oryginalny błąd (UI widzi awarię).
- `parseContextLength` gdy tylko `max_context_length` (bez `loaded_`) → wartość
  z mnożnikiem bezpieczeństwa, nie surowy max.
- `recommendedMaxChars` przy małym kontekście (2048/4096) daje na tyle mały limit,
  że input+echo(reasoning) mieści się w oknie (asercja na górną granicę).

### 6. Workflow obowiązkowy

- `CHANGELOG.md`: wpis pod `## [Unreleased]` (Fixed: długie transkrypty
  faktycznie dzielone; Added: auto-dobór rozmiaru paczki do kontekstu modelu +
  override w Settings), potem przenieść do nowej sekcji `## [x.y.z] - RRRR-MM-DD`.
- `project.yml`: bump `MARKETING_VERSION` (minor) + inkrement `CURRENT_PROJECT_VERSION`.
- `./scripts/rebuild_and_install.sh` na koniec.

## Weryfikacja

1. Testy jednostkowe:
   `xcodebuild -project CustomWhisper.xcodeproj -scheme CustomWhisper -destination "platform=macOS" test -only-testing:CustomWhisperTests/TranscriptCorrectionServiceTests`
   — nowe testy zielone, w szczególności regresja newline-free.
2. E2E z małym modelem: w LM Studio załaduj model z małym kontekstem (np. 4096),
   zaimportuj dłuższe nagranie (kilka–kilkanaście min), uruchom „Correct with
   LM Studio". Oczekiwane: pasek postępu przeskakuje przez wiele paczek (nie 1),
   brak błędu przepełnienia kontekstu, `correctedText` kompletny (bez ucięcia).
3. Fallback: ustaw zły/niedostępny endpoint natywnego API lub model bez detekcji
   → korekta nadal działa na bezpiecznym limicie domyślnym.
4. Override: wpisz w Settings np. 1500 → paczki wyraźnie mniejsze; wyczyść →
   powrót do auto.
5. `./scripts/rebuild_and_install.sh` kończy się sukcesem, aplikacja startuje.

## Inwersja Mungera — czego plan świadomie unika

Pytanie odwrotne: „co zagwarantuje, że mimo chunkowania kontekst i tak się
przepełni albo korekta padnie?" — i jak plan to wyklucza:

1. **Reasoning rozdmuchuje output** (`<think>` w qwen3) → `echoFactor=3.0`,
   budżet liczony na wielokrotność inputu, nie ~1×.
2. **Zły kierunek `charsPerToken`** → obniżony do ~2.0 (gęsty polski = zapas).
3. **Jeden batch zabija całą korektę** → izolacja per-batch (raw + kontynuacja);
   twardy błąd tylko gdy padną wszystkie.
4. **`max_context_length` ≠ realne okno** → preferuj `loaded_context_length`,
   przy max dodatkowy mnożnik.
5. **Over-splitting = kruche sentinele** → tnij na duże kawałki ~limitu, nie per-zdanie.
6. **Niebezpieczny fallback** → domyślny limit zakłada mały kontekst z reasoningiem.
7. **Gwarancja braku overflow „na papierze"**: dla każdego zdania obowiązuje
   twardy cut po znakach, więc żaden fragment NIGDY nie przekracza limitu —
   niezależnie od interpunkcji/języka/CJK.

## Uwagi / ryzyka

- Endpoint `/api/v0/models` LM Studio jest oznaczony jako beta — dlatego twardy
  fallback i override. Jeśli w danej wersji brak `loaded_context_length`,
  `parseContextLength` bierze `max_context_length`, a przy braku obu → nil → fallback.
- `charsPerToken`/`safety` to konserwatywne stałe; przy potrzebie łatwo dostroić.
- Zmiana jest addytywna i lokalna — nie rusza ścieżki dyktowania na żywo ani
  formatu zapisu `MeetingTranscript`.
