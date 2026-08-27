# Intune Configuration Inventory

Reads every policy and configuration in an Intune tenant over Graph REST, writes it to disk
in a form that is stable enough to diff between runs, and produces a change set describing
exactly what was added, changed or removed since last time.

Written because "what changed in this tenant since March?" is a question nobody could answer
without clicking through the portal from memory. The output is deliberately shaped for a
documentation agent to narrate, but it is perfectly readable on its own.

One script, `Export-IntuneConfigurationInventory.ps1`: it reads the tenant and writes a
timestamped run folder, and with `-CompareWithPrevious` it also diffs that run against the
one before it and writes a change set.

The comparison is `Invoke-InventoryComparison`, an internal function that touches nothing
but the filesystem. It was a separate script until 1.9.0; nothing ran it standalone, so it
was folded in. An export of ~170 policies takes a few minutes; the comparison adds seconds.

## The hard requirement

**Two runs against an unchanged tenant must produce byte-identical output.** Without that,
real changes drown in noise and the whole thing is worthless. Most of the design follows
from this one constraint:

- Object keys are sorted with **ordinal** comparison before serialisation. Graph guarantees
  no property order, and culture-aware sorting would order `å ä ö` differently on a Swedish
  workstation than on a build agent elsewhere.
- Rows are sorted deterministically, and column order is fixed.
- `ConfigurationHash` is a SHA256 over exactly the bytes written to the sidecar file, so it
  can be re-verified with `Get-FileHash`.

Verified over four consecutive runs against a production tenant: zero hash differences
across all 172 records.

## What it covers

19 policy areas, all read from `beta` except Conditional Access and group lookups:

Settings Catalog · Device Configuration (Templates) · Group Policy Configuration (ADMX) ·
Endpoint Security (Intents) · Compliance Policies · Remediation Scripts · Platform Scripts
(Windows) · Shell Scripts (macOS) · Autopilot Deployment Profiles · Enrollment
Configurations · Windows Feature/Quality/Driver Update Profiles · App Protection (iOS,
Android) · App Configuration (Managed Apps, Managed Devices) · Assignment Filters ·
Conditional Access (opt-in) · **Applications** (`mobileApps` — Win32, Store, LOB, web link)

Adding an area is one line in `$policyDefinitions` — the pipeline is data-driven and needs
no new code per type.

Not covered: custom compliance scripts, Intune RBAC roles, terms and conditions,
notification templates, imported ADMX files, reusable policy settings, and Endpoint
Analytics. All are one line each if you want them.

## Requirements

**PowerShell 7.4 or later.** Ternary operators, null-coalescing, and
`[System.Security.Cryptography.SHA256]::HashData`. Developed on macOS, run against
production tenants; not yet run on Windows or in Azure Functions.

No modules. Graph is called directly with `Invoke-RestMethod` — no SDK to install, no
version to pin, and no typed deserialisation layer between the response and the hash.

**An Entra ID app registration** with Application permissions and admin consent:

| Permission | Needed for |
|---|---|
| `DeviceManagementConfiguration.Read.All` | Settings Catalog, templates, ADMX, compliance, intents, update profiles |
| `DeviceManagementScripts.Read.All` | Remediations, platform scripts, shell scripts |
| `DeviceManagementApps.Read.All` | App protection and app configuration; also the audit log (`-IncludeAuditActor`) |
| `DeviceManagementServiceConfig.Read.All` | Autopilot, enrollment, assignment filters |
| `Group.Read.All` | Resolving group IDs to names |
| `Organization.Read.All` | Optional — tenant name in the folder name |
| `Policy.Read.All` | Only with `-IncludeConditionalAccess` |

Application, not Delegated — client credentials ignores delegated permissions entirely.
A `ReadWrite` variant satisfies its `Read` counterpart; Graph emits only one of the two.

`DeviceManagementScripts.Read.All` is enforced separately from
`DeviceManagementConfiguration.Read.All`. Without it the three script areas return 403 while
everything else works.

Run `-TestPermissionOnly` first. It decodes the token, prints the tenant and roles, and
names every area the token cannot reach — without reading a single policy.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `INTUNE_TENANT_ID` | Yes | Tenant ID or verified domain |
| `INTUNE_CLIENT_ID` | Yes | App registration client ID |
| `INTUNE_CLIENT_SECRET` | One of these three | App registration secret |
| `INTUNE_CERT_THUMBPRINT` | One of these three | Certificate in the CurrentUser store — alternative to a secret |
| `INTUNE_CERT_PATH` | One of these three | PFX file on disk — alternative to a secret, for stores that don't exist |
| `INTUNE_CERT_PASSWORD` | Only with `INTUNE_CERT_PATH` | PFX password, if the file has one |

```powershell
$env:INTUNE_TENANT_ID     = "..."
$env:INTUNE_CLIENT_ID     = "..."
$env:INTUNE_CLIENT_SECRET = "..."
```

All of these have matching parameters, but prefer the variables. Passing `-ClientSecret` on the
command line puts it in PSReadLine history and any active transcript, and the script warns
when you do.

## Certificate authentication

A certificate is preferred over a client secret and, when one is resolved, always wins over
a secret left in the environment — nothing has to be unset by hand.

**Create and upload the certificate once:**

On Windows:

```powershell
$cert = New-SelfSignedCertificate -Subject "CN=Intune Inventory" -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -NotAfter (Get-Date).AddYears(2)
Export-Certificate -Cert $cert -FilePath intune-inventory.cer
```

`New-SelfSignedCertificate` is Windows-only. On macOS or Linux, `openssl` produces the same
two artefacts — a `.cer` to upload and a `.pfx` for `-CertificatePath`:

```bash
openssl req -x509 -newkey rsa:2048 -keyout intune-inventory.key -out intune-inventory.cer \
    -days 730 -nodes -subj "/CN=Intune Inventory"

openssl pkcs12 -export -out intune-inventory.pfx \
    -inkey intune-inventory.key -in intune-inventory.cer
```

The `.cer` from either command is what gets uploaded to Entra ID; the `.pfx` is what
`-CertificatePath` or `INTUNE_CERT_PATH` points at. `-nodes` above leaves the `.key` file
unencrypted — acceptable for a one-time step, but delete the `.key` once the `.pfx` exists
rather than leaving an unprotected private key on disk. `openssl pkcs12 -export` always
prompts for the PFX's own password interactively unless `-passout` is supplied.

Upload the `.cer` (public part only) to the app registration's **Certificates & secrets**
blade in Entra ID. The private key never leaves wherever it was generated.

**Two sources, same order of precedence as everything else here — explicit parameter, then
environment variable:**

| Source | Parameter / variable | When to use |
|---|---|---|
| Certificate store | `-CertificateThumbprint` / `INTUNE_CERT_THUMBPRINT` | Interactive use. On macOS the `CurrentUser\My` store is the login Keychain; the private key is looked up there and never touches disk as a file. |
| PFX file | `-CertificatePath` (+ `-CertificatePassword`) / `INTUNE_CERT_PATH` (+ `INTUNE_CERT_PASSWORD`) | Unattended runs and Azure Functions, or any environment with no usable certificate store. |

```powershell
# Interactive, from the store
$env:INTUNE_CERT_THUMBPRINT = "0123456789ABCDEF0123456789ABCDEF01234567"
.\Export-IntuneConfigurationInventory.ps1 -Verbose

# Unattended, from a PFX - CertificatePassword is a SecureString, so it comes from the
# environment variable rather than being passed as a plain string on the command line
$env:INTUNE_CERT_PATH     = "./intune.pfx"
$env:INTUNE_CERT_PASSWORD = "..."
.\Export-IntuneConfigurationInventory.ps1
```

`-CertificatePassword` takes a `SecureString`, not a plain string — `-CertificatePassword "text"`
does not work. Let the `INTUNE_CERT_PASSWORD` environment variable populate it, or build one
explicitly with `-CertificatePassword (Read-Host -AsSecureString)`.

**macOS:** signing with a certificate whose private key ACL doesn't list `pwsh` triggers a
Keychain access dialog from Security.framework. That dialog is **not** suppressed by
`pwsh -NonInteractive` — confirmed on a production machine, not a theoretical risk — so a
scheduled run hangs with nothing to answer it. Use `-CertificatePath` for anything unattended
or running in Azure Functions, which has no Keychain to prompt against in the first place;
reserve thumbprint lookup for interactive sessions. And unlike a thumbprint, a PFX file *is*
a credential — keep it out of synchronised folders (OneDrive, Dropbox) and out of version
control, the same as you would a client secret.

### Several customers

For more than one tenant, `-CustomerConfigPath` reads credentials from a local JSON file
instead. `-CustomerName` picks one without prompting; leaving it out prompts — a native
picker on macOS, a numbered console menu elsewhere.

```powershell
cp customers.sample.json ~/.intune/customers.json
chmod 600 ~/.intune/customers.json

./Export-IntuneConfigurationInventory.ps1 -CustomerConfigPath ~/.intune/customers.json
```

Secrets are either inline (`clientSecret`) or resolved through
`Microsoft.PowerShell.SecretManagement` (`secretVault` + `secretName`). A certificate is the
third option, same as for a single tenant: `certificateThumbprint` for the store, or
`certificatePath` (+ optional `certificatePassword`) for a PFX. `customers.sample.json` has
one example of each. Defining a certificate for a customer wins over `clientSecret` or
`secretVault`/`secretName` for that customer, and the script clears `$ClientSecret` when it
does, so a secret left over from the environment or a previously selected customer cannot
shadow it. The confirmation line prints the customer name and tenant ID only, never the
secret or the certificate password, and the script warns if the file is readable beyond its
owner.

**An optional value the selected customer does not define is cleared, not inherited.** That
is the rule the whole design hangs on. `tenantName` names the output folder, so a customer
without one must not pick up the previous customer's — otherwise one tenant's complete
security configuration lands in another tenant's directory. Cleared, it falls back to the
name read from Graph, which is always right for the tenant actually being exported.
`outputDirectory` and `includeConditionalAccess` behave the same way. `jsonDepth` is the
exception: it has a working default, so it is replaced when defined and never cleared.

Explicitly passed parameters beat the file, checked with `$PSBoundParameters.ContainsKey()`,
which is true only for parameters the caller actually supplied. Without
`-CustomerConfigPath`, the environment variables behave exactly as before.

Add the filled-in copy to `.gitignore`.

## Usage

```powershell
# Export, diff against the previous run, and produce a handover zip
./Export-IntuneConfigurationInventory.ps1 -CompareWithPrevious -CompressOutput -Verbose

# Permission check only
./Export-IntuneConfigurationInventory.ps1 -TestPermissionOnly -Verbose

# Fast run without per-policy settings
./Export-IntuneConfigurationInventory.ps1 -SkipDetailedSettings

# Diff against the previous run and record who changed each policy (person vs automation)
./Export-IntuneConfigurationInventory.ps1 -CompareWithPrevious -IncludeAuditActor -Verbose
```

## Output

```
Data/
  Contoso-AB/
    2026-08-05 12-16/
      IntuneConfigurationInventory_Contoso-AB_2026-08-05_1216.csv
      _manifest_2026-08-05_1216.json
      _changeset_vs_2026-07-31-11-25.json
      Settings-Catalog/
        WIN-C-ES-SB-Windows-11_<id>_2026-08-05_1216.json
      Compliance-Policy/
        ...
    Contoso-AB_2026-08-05_1216.zip          ← only with -CompressOutput
```

Folder and file names use **local** time so a run is easy to identify while browsing; the
manifest records the same instant in UTC, in local time, and with the offset, so nothing is
ambiguous. A scheduled run on a UTC host will name its folder in UTC.

### The CSV

One row per policy, fixed column order:

`RunTimestamp` · `RecordKey` · `PolicyArea` · `PolicyType` · `DisplayName` · `Id` ·
`Description` · `Platform` · `TemplateName` · `Version` · `CreatedDateTime` ·
`LastModifiedDateTime` · `AssignedGroups` · `ExcludedGroups` · `AssignmentFilters` ·
`AssignmentIntent` · `AssignmentCount` · `ConfigurationHash` · `ConfigurationFile` · `GraphResourceUri`

The configuration itself lives in a sidecar JSON file, not in the CSV. Inline, single cells
reached 284 000 characters — past Excel's 32 767 limit per cell and past the default field
limit of most CSV readers, including Python's. The sidecar files are written indented so a
per-policy diff is readable line by line.

### Applications

`deviceAppManagement/mobileApps` is read as a single `Application` area covering every app
type. `PolicyType` carries the Graph odata type — `win32LobApp`, `iosStoreApp`,
`macOSPkgApp` — so the platform resolution splits them onto per-platform pages the same way
it does for device configurations.

App assignments carry an **intent** that policy assignments do not, so `AssignmentIntent`
is its own column and its own change signal. An app moving from *required* to *available*
is a real change that the configuration hash would never show, since assignments are
excluded from it.

Three deliberate choices worth knowing:

**`largeIcon` is stripped before hashing**, alongside assignments. It is a base64 PNG worth
tens of kilobytes per Win32 app, and a re-encode by Intune would register as a configuration
change that never happened.

**Supersedence relationships are fetched conditionally** — only when `supersedingAppCount`
or `supersededAppCount` is above zero. That is a handful of apps rather than one request per
app, and it is what lets you spot "app A is superseded by app B but A is still assigned".

**`installSummary` is not part of the configuration or the hash.** `installedDeviceCount`
changes on every device check-in, so including it would report every app as modified on
every run and destroy the whole point of the hash. `-IncludeAppInstallStatus` writes it to a
separate `AppInstallStatus_<stamp>.csv` that is neither hashed nor diffed — useful before a
maintenance window, harmless to the change detection.

Per-assignment settings such as Win32 restart grace periods are stored but are not tracked
as a change signal, since assignments sit outside the hash. A changed restart deadline will
not appear in the diff.

### The manifest

Records every area with `status` (`exported` or `skipped`), `objectCount` and the role it
required. This is what lets a consumer tell **"this area was empty"** from **"we could not
read this area"** — without it, a missing permission looks identical to someone having
deleted every policy in a category.

`exportComplete: false` means at least one area was skipped and the run is not a complete
picture.

### The change set

Produced by the comparison step, grouped into one entry per documentation page — by
category and platform. Change is detected through three independent signals:

- **`ConfigurationHash`** for the policy body.
- **The assignment columns separately.** Assignments are *not* part of the hash, so a policy
  that only gets re-targeted has an unchanged hash. Comparing the hash alone would miss
  re-targeting entirely, which in an Intune tenant is often the change that matters most.
- **The metadata columns** — name, description, version, template.

Changed policies get a field-level JSON diff, matching array elements by identity where one
exists so a reordered array does not read as "everything changed".

Policies missing from an area that was **skipped** in either run are reported as
`uncertain`, never as removed. Absence is not evidence of deletion when the area could not
be read.

### Audit actors

`-IncludeAuditActor` adds one more thing to the change set: for every **added** or
**modified** policy, an `auditActors` list of the Intune audit events in the window since
the previous run whose resources point at that policy.

- **No new Entra permission.** The audit log sits behind `DeviceManagementApps.Read.All`,
  which the app already needs for app protection and app configuration policies.
- **It answers "a person or an automation", not "which technician".** Most writes in a
  tenant are made by its own service principals. In one 30-day measurement, of the events
  that were "someone edited an existing policy", roughly one in twenty-five named a person;
  the rest were apps. The actor is reported as `person`, `app`, or `unknown` — never as a
  `LastModifiedBy`, because that would overclaim.
- **It is a second signal, not the answer.** Service-side drift leaves no audit trail, and
  an audit event can exist with no configuration change. Read the change set and the audit
  list together, not one as an explanation of the other.
- **Privacy.** `actor.ipAddress`, `actor.userId`, `actor.userPermissions` and the audit
  log's own `modifiedProperties` are dropped before anything is written to disk. The
  projected events land in `_auditevents_<stamp>.json` in the run folder; its absence means
  "not fetched", an empty list means "fetched, nothing matched".

Without the switch, no `auditEvents` call is made at all.

### Platform grouping

Graph exposes no platform at all for remediations, platform scripts, Autopilot profiles,
update rings or assignment filters. The comparison resolves it in four steps, first
hit wins: the `Platform` column, then `PolicyType` (which carries the Graph odata type),
then the area's implicit platform, then a peek inside the sidecar file.

Endpoint Security intents carry no platform property either, so theirs is derived from the
`definitionId` prefix of their settings. That is a heuristic on Microsoft's naming, not a
contract — if it stops holding, intents land under Cross-platform, which is the right kind
of failure because it is visible.

Windows 365 is deliberately **not** a separate platform. Graph classifies Cloud PC policies
as Windows, and splitting them out would depend on a naming convention that silently
misfiles anything not following it.

## Error semantics

Worth knowing before you troubleshoot, because Intune's own error mapping is misleading:

**403** means a missing scope for that one area. Intune names the scope it wants
(`Application must have one of the following scopes: ...`). The script skips that area,
records it in the manifest, and continues.

**401 with a generic Forbidden and no scope named** is not a permission problem at all.
Graph wraps an Intune-side rejection as `401 UnknownError`. During development this turned
out to be an expired Intune licence on a developer tenant: Entra ID kept working, `/groups`
answered fine, and every `deviceManagement` endpoint returned 401 regardless of which
identity asked — including a delegated Global Admin token. If you see this, check
`GET /v1.0/subscribedSkus` for a suspended SKU before touching the app registration.

## Data sensitivity

The output contains the tenant's complete security configuration, including script bodies,
BitLocker settings and security baselines. Nothing in the script protects it — the folder
and the zip are unencrypted and inherit the permissions of `-OutputDirectory`.

Do not point `-OutputDirectory` at a synchronised folder unless that is a deliberate
decision, and treat the zip as customer confidential material when handing it over.

## On the code itself

This was written with heavy AI assistance, over about a week rather than a long slow burn.
That is worth saying plainly rather than leaving it to be discovered.

What it has going for it is that essentially every bug was found by **running it against
real tenants**, not by reading it. Four production tenants, 116 to 552 policies each. The
ones worth knowing about:

- An empty Graph `value` array unrolls to `$null` when returned from a PowerShell function,
  which made empty areas look like single objects and inserted the raw response envelope
  into the CSV as phantom rows. Three of them, in a run that otherwise looked clean.
- 172 of 175 records had unsorted JSON keys, so every run produced different hashes. Caught
  by diffing two consecutive runs before trusting the output, not by inspection.
- `ConvertTo-Json -Depth 10` silently truncated 24 policies. Measured maximum depth in a real
  Settings Catalog tree is 12; the default is now 20.
- A 403 on one area aborted the entire run, discarding 122 already-fetched policies.
- `[ValidateNotNullOrEmpty()]` does not run on parameter default values, so an unset
  environment variable produced a request against `login.microsoftonline.com//oauth2/...`
  instead of a clear error.
- Two runs in the same minute got distinct folders but an identical file stamp, so the second
  silently overwrote the first run's zip.
- `#Requires` placed *above* the comment-based help block makes PowerShell fail to find the
  help entirely. `Get-Help` had never worked until this was noticed.

An independent AI review at the end found three real issues and several suggestions. Two
suggestions were rejected with reasoning, and the review missed the zip overwrite above.

Judge it on the behaviour, not the provenance. It is not certified, warrantied or supported.
It only ever issues `GET` requests, so it cannot change anything in a tenant — but read it
before running it against one you care about, and start with `-TestPermissionOnly`.

## Known limitations

- **Applications need a fresh baseline.** The `Application` area and the `AssignmentIntent`
  column were added in export 1.7.0. The first comparison after upgrading reports every
  application as added — set a new baseline deliberately rather than reading that as someone
  having published 300 apps overnight.
- **Beta endpoints throughout.** Required for remediations, shell scripts, driver update
  profiles and intents. Beta can change without notice.
- **N+1 request patterns** in two places: one call per unique group, and one per policy for
  Settings Catalog, ADMX and intent settings. `POST /directoryObjects/getByIds` and
  `POST /$batch` would collapse both, at the cost of POST support and restructuring. Not
  worth it at the scale tested.
- **Endpoint Security exists in two models.** Old `intents` and new `configurationPolicies`
  with a `templateReference`. Both are read, but a policy migrated between them looks
  removed from one area and added to the other.
- **`intents` expose no `createdDateTime`.** That column is always empty for the area.
- **`RecordKey` does not include the tenant ID.** The folder structure separates tenants, but
  there is no column to disambiguate if several customers' CSVs are loaded together.
- **No retention.** Roughly 1.6 MB per run, uncompressed. Scheduled use needs a cleanup.
- **Deleted assignment targets** appear as `<deleted-or-unresolved:guid>`. Deliberately
  visible rather than hidden.

## License

MIT.