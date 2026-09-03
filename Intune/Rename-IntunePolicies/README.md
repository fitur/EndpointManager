# Intune Policy Rename

Exports every Intune policy name to a CSV, and applies an edited copy of that CSV back to the
tenant. Two separate commands, over Graph REST.

One script, `Rename-IntunePolicies.ps1`. It only ever writes `displayName` / `name`. No
assignments, no descriptions, no settings.

**The script has no opinion about what a name should be.** It does not parse names, does not
derive names and knows about no naming convention. What you type in `NewName` is what the
policy is called afterwards.

Three things are true of every run:

- **There is no rollback.** The exported CSV and the run report are the only record of what the
  old names were. Undoing a run means swapping two columns and running the tool again.
- **Mode 1 never writes.** It reads, exports and stops. Everything that touches the tenant
  happens in mode 2, against a CSV a person has edited.
- **A row you did not edit is not touched.** `NewName` comes out pre-filled with `CurrentName`,
  and a row where the two are still equal is skipped.

## Quick start

Five steps. Every step has a fuller section further down.

**1. Check PowerShell.** 7.4 or later.

```powershell
$PSVersionTable.PSVersion
```

**2. Point it at a tenant.** An app registration with Application permissions and admin
consent; see [Requirements](#requirements).

```powershell
$env:INTUNE_TENANT_ID     = '<tenant guid or verified domain>'
$env:INTUNE_CLIENT_ID     = '<app registration client id>'
$env:INTUNE_CLIENT_SECRET = '<secret>'
```

**3. Check the token before anything else.** Reads nothing, writes nothing.

```powershell
./Rename-IntunePolicies.ps1 -TestPermissionOnly
```

**4. Export. This is mode 1 and it changes nothing.**

```powershell
./Rename-IntunePolicies.ps1 -CsvPath ~/Desktop/names.csv -Verbose
```

**5. Edit the `NewName` column, then apply. Dry run first, every time.**

```powershell
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/names.csv -WhatIf
```

```powershell
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/names.csv
```

## The hard requirement

**The CSV is the only rollback that exists.**

Nothing here can undo a rename. Graph has no version history for a policy name, and the tenant
after a run carries no memory of what anything used to be called. Two files stand between a bad
run and a tenant nobody can navigate:

- the **exported CSV** from mode 1, which pairs every `NewName` with the `CurrentName` it
  replaces, and
- the **run report** from mode 2, which records what was actually applied.

Both are written on `-WhatIf` runs too. A dry run you can read afterwards, diff, and hand to
someone else is the point of the dry run.

Three consequences follow from the same constraint:

- **Mode 1 does not rename.** It writes the CSV and returns. There is no combined
  export-and-apply path, because the edit step is where the decisions are made and a flag that
  skips it is a flag that will get used.
- **One confirmation, before the first write, not one per policy.** `ConfirmImpact = 'High'`
  would ask eighteen times, and an operator clicking through eighteen prompts has stopped
  reading by the third. `-Force` skips the single prompt for scheduled runs.
- **A `PATCH` keeps the wide retry set.** Setting a name to a value it may already have is
  idempotent, so replaying one after a 502 that in fact succeeded re-applies the same name.
  This is the opposite of the import script's `POST`, which is retried only on 429 because a
  replay there would create a second policy.

## What it covers

Ten endpoints, all on `beta`:

| Type | Endpoint | Name field | Notes |
|---|---|---|---|
| `Configuration` | `deviceConfigurations` | `displayName` | Abstract base type; `@odata.type` is required in the PATCH body |
| `SettingsCatalog` | `configurationPolicies` | `name` | The one endpoint that does not call it `displayName` |
| `Compliance` | `deviceCompliancePolicies` | `displayName` | Abstract base type |
| `Remediation` | `deviceHealthScripts` | `displayName` | |
| `PlatformScript` | `deviceManagementScripts` | `displayName` | |
| `Filter` | `assignmentFilters` | `displayName` | |
| `WindowsFeatureUpdate` | `windowsFeatureUpdateProfiles` | `displayName` | |
| `WindowsQualityUpdate` | `windowsQualityUpdateProfiles` | `displayName` | |
| `WindowsDriverUpdate` | `windowsDriverUpdateProfiles` | `displayName` | |
| `Autopilot` | `windowsAutopilotDeploymentProfiles` | `displayName` | Abstract base type |

`-PolicyType` restricts a run to some of them; the default is all ten.

**Not covered:** app protection and app configuration policies (MAM), and Enrollment Status Page
configurations (ESP). The endpoints exist in Graph; they are outside this version. They are not
read and not renamed.

## Requirements

**PowerShell 7.4 or later.** Ternary operators and null-coalescing. Developed on macOS 7.6.5.

No modules. Graph is called directly with `Invoke-RestMethod` — no SDK to install and no
version to pin. There is no interactive sign-in. `Microsoft.PowerShell.SecretManagement` is
imported only on the path where a customer entry asks for a vault.

**An Entra ID app registration in the target tenant**, with Application permissions and admin
consent. These are the scopes Graph wants to **update** each resource, read off each endpoint's
own Update page:

| Permission | Types it covers |
|---|---|
| `DeviceManagementConfiguration.ReadWrite.All` | Device configuration templates, Settings Catalog, compliance policies, assignment filters, feature/quality/driver update profiles |
| `DeviceManagementScripts.ReadWrite.All` | Remediation scripts, platform scripts |
| `DeviceManagementServiceConfig.ReadWrite.All` | Autopilot deployment profiles |

Optional: `Organization.Read.All` puts the tenant's display name in the run banner. Without it
the banner shows the tenant GUID, which is still unambiguous.

Application, not Delegated — client credentials ignores delegated permissions entirely.

**A `Read` scope does not satisfy a `ReadWrite` requirement.** It works the other way around,
and only that way: `ReadWrite` covers `Read`, because Graph emits only one of the two claims.
An app registration built for the export script will authenticate here and then 403 on the
first PATCH.

**Assignment filters are the trap, in the opposite direction from the import script.** The
export *reads* `assignmentFilters` with `DeviceManagementServiceConfig.Read.All`, but patching
one needs `DeviceManagementConfiguration.ReadWrite.All`. Autopilot is the one type that really
does need `DeviceManagementServiceConfig.ReadWrite.All` to write. The scope table in the script
was read off the Update documentation for exactly this reason rather than derived from the
export's read scopes.

Run `-TestPermissionOnly` first. It decodes the token and names every selected type it cannot
rename, with the scope each one is missing.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `INTUNE_TENANT_ID` | Yes | Target tenant ID or verified domain |
| `INTUNE_CLIENT_ID` | Yes | App registration client ID |
| `INTUNE_CLIENT_SECRET` | One of these three | App registration secret |
| `INTUNE_CERT_THUMBPRINT` | One of these three | Certificate in the CurrentUser store |
| `INTUNE_CERT_PATH` | One of these three | PFX file on disk, for hosts with no usable store |
| `INTUNE_CERT_PASSWORD` | Only with `INTUNE_CERT_PATH` | PFX password, if the file has one |

All of these have matching parameters, but prefer the variables. Passing `-ClientSecret` on the
command line puts it in PSReadLine history and any active transcript; the script warns when you
do.

## Certificate authentication

A certificate is preferred over a client secret and, when one is resolved, always wins over a
secret left in the environment — nothing has to be unset by hand.

The certificate is created and uploaded exactly as for the export; see that script's README for
the `openssl` and `New-SelfSignedCertificate` commands.

| Source | Parameter / variable | When to use |
|---|---|---|
| Certificate store | `-CertificateThumbprint` / `INTUNE_CERT_THUMBPRINT` | Interactive use. On macOS the `CurrentUser\My` store is the login Keychain. |
| PFX file | `-CertificatePath` (+ `-CertificatePassword`) / `INTUNE_CERT_PATH` (+ `INTUNE_CERT_PASSWORD`) | Unattended runs and Azure Functions, or any environment with no usable certificate store. |

`-CertificatePassword` takes a `SecureString`, not a plain string — `-CertificatePassword "text"`
does not work. Let `INTUNE_CERT_PASSWORD` populate it, or build one with
`-CertificatePassword (Read-Host -AsSecureString)`.

**macOS:** signing with a certificate whose private key ACL doesn't list `pwsh` triggers a
Keychain dialog from Security.framework, and that dialog is **not** suppressed by
`pwsh -NonInteractive`. A scheduled run hangs with nothing to answer it. Use `-CertificatePath`
for anything unattended. A PFX file *is* a credential — keep it out of synchronised folders and
out of version control.

The script warns when the certificate expires within 30 days and refuses to run on an expired
one, because the alternative is an opaque AADSTS error in a scheduled run.

### Several customers

`-CustomerConfigPath` reads credentials from a local JSON file instead of the environment.
`-CustomerName` picks one without prompting; leaving it out prompts — a native picker on macOS,
a numbered console menu elsewhere.

**It is the same file, the same field names and the same four precedence rules as the export and
the import**, so one `customers.json` serves all three. Use the export's `customers.sample.json`
as the template.

```powershell
./Rename-IntunePolicies.ps1 -CustomerConfigPath ~/.intune/customers.json `
    -CustomerName 'Fabrikam AB' -CsvPath ~/Desktop/fabrikam-names.csv
```

The customer selected is the tenant that gets **written to**. The run banner names it, and the
GUID beside the name comes from the token's own `tid` claim rather than from the parameter —
that is the one source that cannot be wrong about which tenant is about to be modified:

```
Source : /Users/you/Desktop/fabrikam-names.csv
Tenant : Fabrikam AB  (4444-…)   WRITE
Rows   : 18 to rename, 3 already named as requested, 0 blocked
```

Add the filled-in copy to `.gitignore`, and `chmod 600` it — the script warns if it is readable
beyond its owner.

## Usage

The two steps are separate commands on purpose. There is no flag that combines them.

```powershell
# 1. Permission check. Reads no policies, writes nothing.
./Rename-IntunePolicies.ps1 -TestPermissionOnly

# 2. Export. Writes the CSV, touches nothing in the tenant.
./Rename-IntunePolicies.ps1 -CsvPath ~/Desktop/names.csv -Verbose

# 3. Edit ~/Desktop/names.csv by hand. See below.

# 4. Dry run. Reads existing names for the collision check, writes the report with whatIf: true.
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/names.csv -WhatIf

# 5. For real. One YES prompt, then the renames.
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/names.csv
```

**Editing the CSV** is step 3, and it is the whole point of the tool:

1. Change `NewName` on the rows you want renamed. Leave the rest alone — a row where `NewName`
   still equals `CurrentName` is skipped, and so is a row where you blank it out.
2. Do not edit `Id` or `GraphType`. They are what the script uses to find the policy.
3. `CurrentName` is not read back for anything except the report and the log lines, so an
   accidental edit there is harmless — but it makes the report harder to read.
4. Names are taken verbatim. Hyphens, dots, dates, Swedish characters, whatever you like;
   nothing is parsed or normalised. The one thing that *is* cleaned up is leading and trailing
   whitespace, which Excel adds freely and which is invisible in the portal and permanent in
   the tenant. The script strips it and warns how many rows it touched.

Narrowing a first run to one type is a good habit:

```powershell
./Rename-IntunePolicies.ps1 -PolicyType Filter -CsvPath ~/Desktop/filters.csv
```

`-Prefix 'Windows - '` restricts the export to policies whose current name starts with a given
string. It filters what is *exported*, not what is *read*: mode 2's collision check still sees
every policy of the affected types, including the ones the prefix excluded.

## Output

### The exported CSV (mode 1)

One row per policy, four columns, UTF-8 **with a BOM**. The BOM is deliberate: in PowerShell 7
`-Encoding UTF8` means UTF-8 *without* one, and Excel then reads the file as Windows-1252. A
policy name containing å, ä or ö would come back from the edited CSV mangled and be written to
the tenant that way.

| Column | What it is |
|---|---|
| `Id` | Graph object ID. Do not edit. |
| `GraphType` | Which endpoint the policy came from. Do not edit. |
| `CurrentName` | The name in the tenant right now. |
| `NewName` | Pre-filled with `CurrentName`. **This is the column you edit.** |

Rows are sorted by `GraphType`, then `CurrentName`.

### The run report (mode 2)

`_renamereport_<yyyy-MM-dd_HHmm>.csv` and `.json`, written next to the source CSV or wherever
`-ReportDirectory` points. Both are written from a `finally` block, so an aborted run still
leaves a record — the case that needs it most is the one that never reaches the end.

Per row: `Id`, `GraphType`, `CurrentName`, `NewName`, `Status`, `Detail`.

| Status | Means |
|---|---|
| `renamed` | Applied. |
| `unchanged` | The policy is already named what the CSV asks for. Re-running the same CSV produces a file of these and no Graph writes. |
| `whatif` | `-WhatIf` run; nothing was sent. |
| `skipped` | Declined at a `-Confirm` prompt. |
| `collision` | Part of a group that would have shared a name. Nothing in the run was applied. |
| `blocked` | Either the token lacks the scope for that type, or that type's existing names could not be read at all, which means uniqueness could not be checked for it. `Detail` says which. |
| `failed` | Graph rejected it. `Detail` carries Graph's own code and message. |

The JSON report also carries `runComplete`, `abortReason`, `whatIf`, the target tenant ID from
the token claim, and a `totals` block with a fixed key list — a status that did not occur reads
as `0` rather than being missing, because "no rows" and "did not happen" are different states.

### Collisions

This is the only judgment the script makes about a name, and it is not an opinion about naming.
Intune enforces unique names **per policy type**, so a run that produced a duplicate would fail
partway through and leave the tenant half-renamed.

Before anything is written, the script works out what every policy of every affected type will
be called when the run finishes, and looks for two that land on the same name. That covers three
cases a simple duplicate check does not:

- two rows in the CSV mapping to one name,
- a rename colliding with a policy nobody is touching,
- a name that looks taken but is being vacated by another row in the same run — reported as
  fine, because it is.

On a collision the whole group is printed, with every ID and current name in it, and mode 2
aborts before the first PATCH. **`-Force` does not get past this.** A bad name can be fixed by
running the tool again; two identically named policies cannot, because by then the collision is
already in the tenant.

The same reasoning is why the same `Id` appearing on two rows is rejected outright: whichever
ran last would win, and which that is depends on row order.

**If a type's existing names cannot be read at all** — a 403 partway through the check, most
often — its rows are not treated as collision-free by default. An empty read is "we do not
know," not "no collisions." Those rows are recorded as `blocked` before anything else runs, and
mode 2 continues with the types it could verify.

## Error semantics

**403** means a missing scope for that one type. Intune names the scope it wants. The row is
recorded as `blocked`, the type is marked, and the remaining rows of that type are recorded
without another call — one line each, not one failing request each. A 403 while reading a
type's *existing* names — before any PATCH is attempted, during the collision check — blocks
every row of that type the same way, since uniqueness could not be verified for it either.

**401** is global: the token itself is not accepted. One automatic refresh covers a genuinely
stale token; a second 401 aborts the run. The report is still written, with
`runComplete: false`.

**401 with a generic message that names no scope** is not a permission problem at all. Graph
wraps an Intune-side rejection this way, and on a developer tenant it usually means an expired
Intune licence: Entra ID keeps working, `/groups` answers fine, and every `deviceManagement`
endpoint returns 401 no matter who asks. Check `GET /v1.0/subscribedSkus` before touching the
app registration.

**400** is why `Get-GraphErrorDetail` exists. `Invoke-RestMethod` puts the response body in
`ErrorDetails.Message` and its own exception says only `400 (Bad Request)`. The report gets the
full thing, so a name Intune rejects is legible:

```
Response status code does not indicate success: 400 (Bad Request). |
BadRequest: Entity only allows writes with a JSON Content-Type header.
```

**404** on a PATCH means the `Id` in the CSV is not in the tenant — usually a row edited by
hand, or a policy deleted since the export was written. `Detail` carries Graph's own
`ResourceNotFound` text.

**429 and 5xx** are retried with backoff, honouring `Retry-After` when Graph sends it.

## Data sensitivity

The exported CSV and the run report list **every policy name in the tenant together with its
object ID**. That is a map of the customer's security configuration: what is deployed, roughly
what it does, and enough identifiers to address any of it through Graph. Neither file is
encrypted, and both inherit the permissions of the folder they are written to.

Do not leave either in a synchronised folder (OneDrive, Dropbox) unless that is a deliberate
decision, and treat both as customer confidential when handing them over.

`-ReportDirectory` exists so the report does not have to live next to the CSV. That matters when
the CSV came from somewhere shared.

## Known limitations

- **There is no rollback.** To undo a run, open `_renamereport_<stamp>.csv`, swap the
  `CurrentName` and `NewName` columns, save it as a new file and run mode 2 against it:

  ```powershell
  ./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/undo.csv -WhatIf
  ```

  The reversed file needs the same four columns — `Id`, `GraphType`, `CurrentName`, `NewName`.
  Because the script validates nothing about the names themselves, a reversal always passes
  validation; what it cannot do is bring back a policy that was deleted in between.

- **A possible extra `GET` per renamed policy on three endpoints.** `deviceConfigurations`,
  `deviceCompliancePolicies` and `windowsAutopilotDeploymentProfiles` are abstract base types
  whose PATCH body must name the derived type. The collision check already reads every policy
  of these types and carries the derived type along, so in the normal case nothing extra is
  fetched. The GET is a fallback for an Id the collision-check read did not cover — most often
  a hand-edited CSV row.

- **Names are not validated.** Length limits, reserved characters and duplicate-name rules
  beyond the per-type uniqueness check are left to Graph. A name Intune rejects comes back as a
  `failed` row with Graph's own message, not as a local error.

- **Excel can rewrite `NewName` for you, silently.** A policy name that looks like a date or a
  number — `2025-03-13`, `1.5`, `03-2025`, `SEP-25` — is converted the moment the file is opened
  and saved back in the new format. That makes `NewName` differ from `CurrentName` even though
  nobody meant to change anything, and the script has no way to tell that apart from a real
  edit: the mangled value gets PATCHed in. Trimming whitespace does not catch this — it is not
  whitespace, it is a different value. Open the CSV with **Data → Get Data → From Text/CSV** and
  set the column type to **Text**, or edit it in a plain text editor instead.

- **Only the name is written.** Assignments, descriptions and settings are never touched, and
  renaming does not affect any of them.

- **`-Prefix` matches with `-like`,** so `*` and `?` in the prefix are wildcards. That is
  usually what you want; it is worth knowing if a policy name contains one.

- **MAM and ESP cannot be renamed.** Out of scope for this version; the endpoints are not read
  at all.

- **Beta endpoints throughout.** Required for remediations and driver update profiles. Beta can
  change without notice.

- **Shared authentication code has drifted, on purpose.** `Get-ClientCertificate` now exists in
  four files — this one, the export, the import and `New-IntuneWin32AppJson.ps1` — in different
  versions, and `ConvertTo-Base64Url` and `New-ClientAssertion` in three. The copies here were
  taken verbatim from the export on 2026-09-01. Do not "resynchronise" them by pasting one copy
  over another; the win32 copy takes a `[string]` password and catches only
  `PlatformNotSupportedException`, which the export widened deliberately.

## License

MIT.
