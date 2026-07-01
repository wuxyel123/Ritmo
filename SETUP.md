# Ritmo — Guida Setup Xcode

## Struttura del progetto

```
Ritmo/
├── Packages/
│   └── RitmoCore/          ← Swift Package condiviso (modelli, repo, servizi)
├── Ritmo iOS/              ← App iPhone (target principale)
├── Ritmo watchOS/          ← App Apple Watch
├── Ritmo Widgets/          ← Widget (iOS + macOS + Watch)
└── SETUP.md                  ← questa guida
```

---

## Passo 1 — Crea il progetto Xcode

1. Apri Xcode → **Create New Project**
2. Scegli **iOS → App**
3. Nome: `Ritmo`
4. Bundle ID: `com.tuonome.ritmo` *(sostituisci con il tuo)*
5. Interface: **SwiftUI**
6. Language: **Swift**
7. Spunta **Include Tests**
8. Scegli la cartella dove salvare

---

## Passo 2 — Aggiungi i target Watch e Widget

### Apple Watch
1. **File → New → Target**
2. Scegli **watchOS → Watch App**
3. Nome: `Ritmo watchOS`
4. Assicurati che "Include Notification Scene" sia **deselezionato**

### Widget Extension
1. **File → New → Target**
2. Scegli **iOS → Widget Extension**
3. Nome: `Ritmo Widgets`
4. Spunta **Include Live Activity** se vuoi (opzionale)

---

## Passo 3 — Aggiungi il Swift Package locale

1. **File → Add Package Dependencies**
2. Scegli **Add Local...**
3. Naviga alla cartella `Packages/RitmoCore`
4. Clicca **Add Package**
5. Aggiungi `RitmoCore` a **tutti i target**: iOS, watchOS, Widget

---

## Passo 4 — Configura HealthKit (OBBLIGATORIO)

### Per il target iOS:
1. Seleziona il target `Ritmo` → **Signing & Capabilities**
2. Clicca **+ Capability**
3. Aggiungi **HealthKit**

### Per il target watchOS:
1. Seleziona `Ritmo watchOS` → **Signing & Capabilities**
2. Aggiungi **HealthKit**

### Info.plist (iOS e watchOS):
Aggiungi queste chiavi (Xcode le aggiunge automaticamente con HealthKit, ma verifica):

```xml
<key>NSHealthShareUsageDescription</key>
<string>Ritmo legge i tuoi dati di salute (passi, sonno, frequenza cardiaca, nutrizione) per mostrarti grafici e insights personalizzati.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Ritmo non scrive dati su Apple Health.</string>
```

---

## Passo 5 — Configura CloudKit (sync iPhone → Mac)

1. Seleziona target `Ritmo` → **Signing & Capabilities**
2. Aggiungi **iCloud**
3. Spunta **CloudKit**
4. Aggiungi **Background Modes** → spunta **Background fetch** e **Remote notifications**

> CloudKit sincronizza automaticamente SwiftData tra tutti i dispositivi dell'utente
> (iPhone → Mac, iPhone → iPad).

---

## Passo 6 — Configura App Group (per Widget e Watch)

L'App Group permette alla app principale di condividere dati con Widget e Watch.

1. Target **Ritmo** → **Signing & Capabilities** → **+ Capability** → **App Groups**
2. Aggiungi: `group.com.tuonome.ritmo`
3. Fai lo stesso per `Ritmo Widgets` e `Ritmo watchOS`

> Sostituisci `tuonome` con il tuo Apple Developer Team ID o nome.

---

## Passo 7 — Mac Catalyst

1. Seleziona target `Ritmo` → **General**
2. Sotto **Deployment Info** → spunta **Mac** (Catalyst)
3. Xcode aggiungerà automaticamente il target macOS

---

## Passo 8 — Copia i file

Trascina i file dalle cartelle del progetto in Xcode:

| File | Target |
|------|--------|
| `Ritmo iOS/RitmoApp.swift` | Ritmo (iOS) |
| `Ritmo iOS/Features/*.swift` | Ritmo (iOS) |
| `Ritmo watchOS/RitmoWatchApp.swift` | Ritmo watchOS |
| `Ritmo Widgets/RitmoWidgets.swift` | Ritmo Widgets |

I file in `Packages/RitmoCore/` vengono inclusi automaticamente via Swift Package.

---

## Passo 9 — Colori & Assets

In `Assets.xcassets`, crea il colore `AccentColor`:
- Light mode: `#6C5CE7` (viola)
- Dark mode: `#A29BFE` (viola chiaro)

---

## Passo 10 — Test su dispositivo fisico

> ⚠️ HealthKit non funziona nel simulatore — serve un iPhone fisico.

1. Connetti il tuo iPhone
2. Seleziona il dispositivo in Xcode
3. ⌘R per buildare e installare
4. Alla prima apertura, accetta tutti i permessi HealthKit

### Verifica che Yazio stia scrivendo su HealthKit:
Apri **Salute** → Sfoglia → Nutrizione → assicurati che Yazio sia elencato come sorgente.

---

## Struttura file Swift Package (RitmoCore)

```
Sources/RitmoCore/
├── Models/
│   ├── WorkoutModels.swift     (WorkoutSession, WorkoutSet, Exercise, UserGoals)
│   └── HealthModels.swift      (NutritionDay, SleepSession, DailyActivity, DailySnapshot)
├── Repositories/
│   └── HealthKitRepository.swift
├── Services/
│   └── PRAndInsightsService.swift
└── Storage/
    └── RitmoStore.swift       (SwiftData + CloudKit)
```

---

## Note importanti

- **Apple Developer Account**: serve per testare HealthKit su dispositivo fisico (account gratuito è sufficiente). Per distribuire su App Store serve l'account a pagamento ($99/anno).
- **Privacy**: tutti i dati restano sul dispositivo o nell'iCloud privato dell'utente. Ritmo non ha un backend.
- **CloudKit**: la sync funziona solo se l'utente ha iCloud attivo e ha effettuato il login con Apple ID.
