# Intune Policy Rename

Renames Intune policies to the naming standard `OS-SCOPE-TARGET-TYP-KAT-Name`, over Graph
REST, in two deliberate steps: propose to a CSV, review the CSV, then apply it.

One script, `Rename-IntunePolicies.ps1`. It only ever writes `displayName` / `name`. No
assignments, no descriptions, no settings.

Three things are true of every run and worth knowing before the first one:

- **There is no rollback.** The proposal CSV and the run report are the only record of what the
  old names were. Undoing a run means swapping two columns and running the tool again.
- **Mode 1 never writes.** It reads, proposes and stops. Everything that touches the tenant
  happens in mode 2, against a CSV a person has looked at.
- **A name that already follows the standard is left alone.** Running the tool twice is a
  no-op, not a second round of renaming. This is checked before any interpretation of the name
  happens, and it is the property most of the design exists to protect.

## Quick start

Five steps from nothing to renamed policies. Every step has a fuller section further down.

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

**4. Propose. This is mode 1 and it changes nothing.**

```powershell
./Rename-IntunePolicies.ps1 -CsvPath ~/Desktop/rename.csv -Verbose
```

Now open `~/Desktop/rename.csv`, sort by `Confidence`, and read it. See
[Output](#output) for what the columns mean. Edit the `NewName` column where the script guessed
wrong; blank it out for any row you do not want touched.

**5. Apply. Dry run first, every time.**

```powershell
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/rename.csv -WhatIf
```

```powershell
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/rename.csv
```

## The hard requirement

**The CSV is the only rollback that exists. Review it.**

Nothing here can undo a rename. Graph has no version history for a policy name, and the tenant
after a run carries no memory of what anything used to be called. Two files stand between a bad
run and a tenant nobody can navigate:

- the **proposal CSV** from mode 1, which pairs every `NewName` with the `CurrentName` it
  replaces, and
- the **run report** from mode 2, which records what was actually applied.

Both are written on `-WhatIf` runs too. A dry run you can read afterwards, diff, and hand to
someone else is the point of the dry run.

Three consequences follow from the same constraint:

- **Mode 1 does not rename.** It writes the CSV and returns. There is no combined
  propose-and-apply path, because the review step is the safety mechanism and a flag that skips
  it is a flag that will get used.
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

**Not covered:** app protection and app configuration policies (MAM), Enrollment Status Page
configurations (ESP), and the `SYS` type in the standard. The endpoints exist in Graph; they
are outside this version. They are not read, not proposed and not renamed.

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
    -CustomerName 'Fabrikam AB' -CsvPath ~/Desktop/fabrikam-rename.csv
```

The customer selected is the tenant that gets **written to**. The run banner names it, and the
GUID beside the name comes from the token's own `tid` claim rather than from the parameter —
that is the one source that cannot be wrong about which tenant is about to be modified:

```
Source : /Users/you/Desktop/fabrikam-rename.csv
Tenant : Fabrikam AB  (4444-…)   WRITE
Rows   : 18 to rename, 3 already named as requested, 1 refused as unresolved
```

Add the filled-in copy to `.gitignore`, and `chmod 600` it — the script warns if it is readable
beyond its owner.

## Usage

The two steps are separate commands on purpose. There is no flag that combines them.

```powershell
# 1. Permission check. Reads no policies, writes nothing.
./Rename-IntunePolicies.ps1 -TestPermissionOnly

# 2. Propose. Writes the CSV, touches nothing in the tenant.
./Rename-IntunePolicies.ps1 -CsvPath ~/Desktop/rename.csv -Verbose

# 3. Review ~/Desktop/rename.csv by hand. See below.

# 4. Dry run. Reads existing names for the collision check, writes the report with whatIf: true.
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/rename.csv -WhatIf

# 5. For real. One YES prompt, then the renames.
./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/rename.csv
```

**Reviewing the CSV** is step 3 and it is not optional:

1. Sort by `Confidence`. The file is already written in that order — `Unresolved` first, then
   `Assumed`, then the rest — so the rows that need a human are at the top.
2. `Unresolved` rows have an empty `NewName`. Fill one in, or leave the row alone and it is
   skipped. Read `Reason` to see what the script could not establish.
3. `Assumed` rows have a name, but at least one segment is a default rather than something that
   was read. In practice that is usually `SCOPE` — the script cannot know whether a policy is
   Base or Custom, so it writes `C`. Change `C` to `B` where it should be.
4. Blank the `NewName` of anything you do not want renamed.
5. Do not edit `Id` or `GraphType`. They are what the script uses to find the policy.

Narrowing a first run to one type is a good habit:

```powershell
./Rename-IntunePolicies.ps1 -PolicyType Filter -CsvPath ~/Desktop/filters.csv
```

`-Prefix 'Windows - '` restricts the proposal to policies whose current name starts with a
given string. It filters what is *proposed*, not what is *read*: the collision check still sees
every policy of the affected types, including the ones the prefix excluded.

## Output

### The proposal CSV (mode 1)

One row per policy, UTF-8 **with a BOM**. The BOM is deliberate: in PowerShell 7 `-Encoding
UTF8` means UTF-8 *without* one, and Excel then reads the file as Windows-1252. A policy name
containing å, ä or ö would come back from the reviewed CSV mangled and be written to the tenant
that way.

| Column | What it is |
|---|---|
| `Id` | Graph object ID. Do not edit. |
| `GraphType` | Which endpoint the policy came from. Do not edit. |
| `CurrentName` | The name in the tenant right now. |
| `NewName` | The proposal. Edit this, or blank it to skip the row. |
| `Os` `Scope` `Target` `Typ` `Kat` | The individual segments, so a wrong one is visible without parsing the name. |
| `Confidence` | How the name was arrived at. See below. |
| `Reason` | One line naming every assumption and every gap. |
| `Changed` | Whether `NewName` differs from `CurrentName`. |

### Confidence

**Read this column row by row.** It is the difference between a name the script *read* and a
name it *chose*.

| Level | Means | Mode 2 |
|---|---|---|
| `Compliant` | The current name already follows the standard. | Skipped, never rewritten |
| `Derived` | Read from a Graph field, or from an explicit word in the current name. | Applied |
| `Assumed` | An endpoint default that holds for the large majority, but was **not read**. `Reason` names the assumption. | Applied |
| `Unresolved` | No basis at all. `NewName` is empty. | Refused, unless `-AllowUnresolved` |

`Assumed` exists because a strict two-level model would make the entire Settings Catalog —
the largest area in most tenants — `Unresolved`, and the flag meant to be the exception would
become the normal way to run the tool. The assumption is still visible and still named; what it
is not is silent.

A row's confidence is the **weakest** of its segments. One assumed segment makes the whole row
`Assumed`; one unresolved segment makes it `Unresolved` and empties `NewName`, so there is
never a half-derived suggestion sitting in the file waiting to be approved by accident.

### The run report (mode 2)

`_renamereport_<yyyy-MM-dd_HHmm>.csv` and `.json`, written next to the source CSV or wherever
`-ReportDirectory` points. Both are written from a `finally` block, so an aborted run still
leaves a record — the case that needs it most is the one that never reaches the end.

Per row: `Id`, `GraphType`, `CurrentName`, `NewName`, `Status`, `Detail`.

| Status | Means |
|---|---|
| `renamed` | Applied. |
| `compliant` | The policy is already named what the CSV asks for. Re-running the same CSV produces a file of these and no Graph writes. |
| `whatif` | `-WhatIf` run; nothing was sent. |
| `skipped` | Declined at a `-Confirm` prompt. |
| `unresolved` | `Confidence` was `Unresolved` and `-AllowUnresolved` was not passed. |
| `collision` | Part of a group that would have shared a name. Nothing in the run was applied. |
| `blocked` | The token lacks the scope for that type. |
| `failed` | Graph rejected it. `Detail` carries Graph's own code and message. |

The JSON report also carries `runComplete`, `abortReason`, `whatIf`, the target tenant ID from
the token claim, and a `totals` block with a fixed key list — a status that did not occur reads
as `0` rather than being missing, because "no rows" and "did not happen" are different states.

### Collisions

Intune enforces unique names **per policy type**, not globally. Before anything is written, the
script works out what every policy of every affected type will be called when the run finishes
and looks for two that land on the same name. That covers three cases a simple duplicate check
does not:

- two rows in the run mapping to one name,
- a rename colliding with a policy nobody is touching,
- a name that looks taken but is being vacated by another row in the same run — reported as
  fine, because it is.

On a collision the whole group is printed, with every ID and current name in it, and mode 2
aborts before the first PATCH. **`-Force` does not get past this.** A bad name can be fixed by
running the tool again; two identically named policies cannot, because by then the collision is
already in the tenant.

## Error semantics

**403** means a missing scope for that one type. Intune names the scope it wants. The row is
recorded as `blocked`, the type is marked, and the remaining rows of that type are recorded
without another call — one line each, not one failing request each.

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
full thing, so a missing `@odata.type` or a name Intune rejects is legible:

```
Response status code does not indicate success: 400 (Bad Request). |
BadRequest: Entity only allows writes with a JSON Content-Type header.
```

**404** on a PATCH means the `Id` in the CSV is not in the tenant — usually a row edited by
hand, or a policy deleted since the proposal was written. `Detail` carries Graph's own
`ResourceNotFound` text.

**429 and 5xx** are retried with backoff, honouring `Retry-After` when Graph sends it.

## Data sensitivity

The proposal CSV and the run report list **every policy name in the tenant together with its
object ID**. That is a map of the customer's security configuration: what is deployed, roughly
what it does, and enough identifiers to address any of it through Graph. Neither file is
encrypted, and both inherit the permissions of the folder they are written to.

Do not leave either in a synchronised folder (OneDrive, Dropbox) unless that is a deliberate
decision, and treat both as customer confidential when handing them over.

`-ReportDirectory` exists so the report does not have to live next to the CSV. That matters
when the CSV came from somewhere shared.

## Known limitations

- **There is no rollback.** To undo a run, open `_renamereport_<stamp>.csv`, swap the
  `CurrentName` and `NewName` columns, save it as a new file and run mode 2 against it:

  ```powershell
  ./Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/undo.csv -WhatIf
  ```

  The reversed file needs the same four columns — `Id`, `GraphType`, `CurrentName`, `NewName` —
  and the old names have to satisfy the standard, or the format check rejects them. A run that
  moved a policy *to* the standard cannot be reversed this way if the original name was not
  itself standard-compliant; in that case the report is a record you apply by hand.

- **`Confidence` must be reviewed row by row.** `Assumed` means the script chose an endpoint
  default, not that it read the value. `Unresolved` means it had nothing to go on, and those
  rows are refused unless `-AllowUnresolved` is passed.

- **Antivirus and VPN profiles get no category.** The standard has no `AV` under `ES` and no VPN
  category under `CP` (`ES`: BTL, ASR, SB, AP, FW, EDR; `CP`: SC, OMA, CRT, WFI, WHM). Earlier
  versions mapped antivirus to a non-existent `ES-AV` and VPN to `CP-WFI`, which is a Wi-Fi
  category. Both now resolve as far as the type and stop, and come out `Unresolved`. This is a
  gap in the standard, not in the script — raise it with the standard's owner.

- **`WindowsDriverUpdate` is mapped to `WU-QU`.** There is no driver category in the standard.
  The mapping is recorded as `Assumed` and named in `Reason`.

- **The standard's TYP list has no `SC`, but its category table has `SC: PS, SH`.** The script
  treats `SC` as a valid type, which is what makes platform scripts nameable at all.

- **Filters: `TARGET` and `KAT` are not the same axis.** The standard's own example,
  `WIN-B-USR-FI-DEV-Default`, pairs `TARGET=USR` with `KAT=DEV`. The script reads `TARGET` from
  `assignmentFilterManagementType` (`devices` → `DEV`, `apps` → `USR`) and fixes `KAT=DEV` from
  the endpoint. That reproduces the example exactly, but it is an inference from one example
  rather than a documented rule — **verify it against a real filter before running mode 2 on
  filters in production.**

- **`TARGET` is assumed for Settings Catalog and device configuration templates.** Graph does
  not expose whether such a policy is user- or device-scoped, so both come out `DEV`, marked
  `Assumed`. Every other type reads it or is device-only by construction.

- **`SCOPE` has no Graph source at all.** Base versus Custom is an internal classification. A
  name with no `Base`/`Custom` token gets `-DefaultScope` (default `C`), marked `Assumed`. This
  is the single most common thing to correct in the CSV.

- **MAM, ESP and SYS cannot be renamed.** Out of scope for this version; the endpoints are not
  read at all.

- **Only the name is written.** Assignments, descriptions and settings are never touched, and
  renaming does not affect any of them.

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
