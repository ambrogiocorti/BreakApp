# BreakApp — Super Admin esclusivamente globale (decisione confermata)

**Modifica esplicitamente richiesta:** «Se io sono Super Admin, non voglio poter essere Cliente».

Questo vincolo precisa l'eccezione al requisito generale del Prompt Master §2.2, che consente ad altri account di avere ruoli diversi in più scuole. **Per un account assegnato in `app_private.platform_admins`, il contesto operativo Super Admin è esclusivo.**

## Comportamento

- Dopo il login il backend verifica la presenza del ruolo Super Admin con la RPC `has_current_platform_admin_role()`, indipendentemente dal livello MFA corrente.
- Se il risultato è positivo, la sidebar propone esclusivamente **Piattaforma** e **Profilo e sicurezza**. Nessuna voce Menu, Ordini Cliente o ruolo di scuola compare nel selettore, nemmeno quando un account conserva vecchie membership scolastiche.
- Se l'account è Super Admin ma non ha raggiunto AAL2, il solo Profilo rimane accessibile per completare la 2FA; **non si ripiega su Cliente**.
- Un valore `localStorage` precedentemente salvato come Cliente viene scartato e sostituito dal contesto globale.
- Un errore nella verifica del ruolo non viene interpretato come assenza di ruolo: l'interfaccia resta chiusa fino a una verifica valida.
- Il database ha un trigger su `public.orders` che vieta di inserire nuovi ordini assegnati agli utenti presenti in `app_private.platform_admins`, anche tramite chiamate API fuori dall'interfaccia.
- Gli ordini storici eventualmente creati in precedenza non vengono cancellati o alterati.

## Casi verificati

- Super Admin con precedenti membership Cliente/Admin/Barista: **solo Super Admin**.
- Super Admin AAL1: nessuna interfaccia Cliente e pannello globale ancora bloccato.
- Cliente normale: mantiene Menu e Ordini.
- Un account multiruolo che **non** è Super Admin mantiene il modello di ruoli per scuola.
- Tentativo server di inserire un ordine per un Super Admin: rifiutato.
- Inserimento per un Cliente normale: accettato nel database temporaneo usato per i test.

## Note

Questa eccezione non promuove automaticamente nessun altro account a Super Admin: la membership rimane server-side e non modificabile dal browser. Non sono stati toccati i pagamenti o gli ordini storici.
