# Intune Configuration Import

Takes the sidecar JSON files produced by `Export-IntuneConfigurationInventory.ps1` and creates
those policies in a different Intune tenant, one `POST` per file, over Graph REST.

Written for the case the export leaves open: you have customer A's configuration on disk and
you want it in customer B's tenant without rebuilding it by hand in the portal.

Two things are true of every run and worth knowing before the first one:

- **Everything is created unassigned.** No groups, no filters, no assignment intent. Assigning
  is a deliberate second step in the portal, not something a bulk import should guess at.
- **There is no rollback.** The script only ever creates. It cannot update, cannot delete, and
  cannot undo half a run. The import report is the only record of what was created — which is
  why it is written even when the run is aborted.

One script, `Import-IntuneConfigurationFromJson.ps1`. The area folder name decides which Graph
endpoint each file is posted to; the script never guesses an endpoint from a file's contents.

## Quick start

Six steps from an export folder to policies in a target tenant. Every step has a fuller
section further down.

**1. Check PowerShell.** 7.4 or later.

```powershell
$PSVersionTable.PSVersion
```

**2. Unpack the export.** Run folders from export 1.12.0 and later hold the area folders inside
`<Tenant>_<stamp>_sidecars.zip`, not loose. The import needs them unpacked.

```powershell
Expand-Archive -Path './Contoso-AB_2026-08-20_0914_sidecars.zip' -DestinationPath ~/Import
```

**3. Create an Entra ID app registration in the TARGET tenant** and grant admin consent for
these *Application* permissions — Application, not Delegated, and `ReadWrite`, not `Read`:

`DeviceManagementConfiguration.ReadWrite.All`, `DeviceManagementScripts.ReadWrite.All`,
`DeviceManagementApps.ReadWrite.All`, `DeviceManagementServiceConfig.ReadWrite.All`

**4. Give the script a credential** for that app registration.

```powershell
$env:INTUNE_TENANT_ID     = '<target-tenant-guid>'
$env:INTUNE_CLIENT_ID     = '<app-guid>'
$env:INTUNE_CLIENT_SECRET = '<secret>'
```

**5. Check the token before writing anything.**

```powershell
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -TestPermissionOnly
```

Expect `AllAreasReady : True`. Anything under `BlockedAreas` names the scope it is missing.
This step reads nothing, writes nothing and posts nothing.

**6. Dry run, then for real.**

```powershell
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -WhatIf -Verbose
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -Area 'Assignment-Filter'
```

Do the real run one area at a time, at least the first time. Both runs write an
`_importreport_<stamp>.json` into the source folder; `whatIf` in it tells them apart.

**More than one tenant?** Skip step 4 and put the credentials in a file instead — see
[Several customers](#several-customers).

## The hard requirement

**Nothing is created that a `-WhatIf` run has not already shown, and everything that is
created is on disk before the process can exit.**

There is no rollback. When half a run fails, the import report is all that is left, so it is
written from a `finally` block rather than after the loop — the case that needs it most is the
one that never reaches the end. A global 401 halfway through leaves real objects in the target
tenant that exist nowhere else in writing, and the report is what tells you which ones.

That is also why the report is written on a `-WhatIf` run. A dry run you can read afterwards,
diff, and hand to someone else is the point of the dry run.

Two consequences that follow from the same constraint:

- **A `POST` is retried only on 429.** A 5xx or a dropped connection can happen *after* the
  service has already created the policy, so replaying it would create a second copy. 429 means
  the request was rejected before it was processed, which makes it the one status that is safe.
  `GET` keeps the export's wider retry set.
- **One confirmation, before the first write, not one per object.** `ConfirmImpact = 'High'`
  would ask eighteen times, and an operator clicking through eighteen prompts has stopped
  reading by the third.

## What it covers

14 areas, all posted to `beta`:

| Area folder | Graph resource |
|---|---|
| `Assignment-Filter` | `deviceManagement/assignmentFilters` |
| `Settings-Catalog` | `deviceManagement/configurationPolicies` |
| `Device-Configuration-Templates` | `deviceManagement/deviceConfigurations` |
| `Compliance-Policy` | `deviceManagement/deviceCompliancePolicies` |
| `Remediation-Script` | `deviceManagement/deviceHealthScripts` |
| `Platform-Script-Windows` | `deviceManagement/deviceManagementScripts` |
| `Shell-Script-macOS` | `deviceManagement/deviceShellScripts` |
| `Autopilot-Deployment-Profile` | `deviceManagement/windowsAutopilotDeploymentProfiles` |
| `Windows-Feature-Update-Profile` | `deviceManagement/windowsFeatureUpdateProfiles` |
| `Windows-Quality-Update-Profile` | `deviceManagement/windowsQualityUpdateProfiles` |
| `Windows-Driver-Update-Profile` | `deviceManagement/windowsDriverUpdateProfiles` |
| `App-Protection-Policy-iOS` | `deviceAppManagement/iosManagedAppProtections` |
| `App-Protection-Policy-Android` | `deviceAppManagement/androidManagedAppProtections` |
| `App-Configuration-Managed-Apps` | `deviceAppManagement/targetedManagedAppConfigurations` |

Five more areas appear in an export and are **not** importable. They are listed explicitly in
the script so a run reports them with the reason rather than leaving you wondering why a folder
was ignored — see [Known limitations](#known-limitations).

A sidecar is a record of what a policy looked like, not a request body. Three things happen to
each file before it is posted: the service-owned properties are stripped, the double-wrapped
`settings` array written by exports before 1.11.0 is flattened, and the required properties are
checked up front so a file that cannot produce a valid policy is reported rather than
half-created.

Duplicates are handled by reading the existing display names once per area. A file whose name
matches something already in the target tenant is skipped and reported.

## Requirements

**PowerShell 7.4 or later.** Ternary operators and null-coalescing. Developed on macOS 7.6.5,
run against production tenants.

No modules. Graph is called directly with `Invoke-RestMethod` — no SDK to install and no
version to pin. `Microsoft.PowerShell.SecretManagement` is imported only on the path where a
customer entry asks for a vault.

**An Entra ID app registration in the target tenant**, with Application permissions and admin
consent. These are the scopes Graph wants to **create** each resource, read off each endpoint's
own Create page:

| Permission | Areas it covers |
|---|---|
| `DeviceManagementConfiguration.ReadWrite.All` | Assignment filters, Settings Catalog, device configuration templates, compliance policies, feature/quality/driver update profiles |
| `DeviceManagementScripts.ReadWrite.All` | Remediation scripts, platform scripts (Windows), shell scripts (macOS) |
| `DeviceManagementApps.ReadWrite.All` | App protection (iOS, Android), app configuration (managed apps) |
| `DeviceManagementServiceConfig.ReadWrite.All` | Autopilot deployment profiles |

Application, not Delegated — client credentials ignores delegated permissions entirely.

**A `Read` scope does not satisfy a `ReadWrite` requirement.** It works the other way around,
and only that way: `ReadWrite` covers `Read`, because Graph emits only one of the two claims.
An app registration built for the export will authenticate here and then 403 on the first POST.

**Assignment filters are the trap.** The export *reads* `assignmentFilters` with
`DeviceManagementServiceConfig.Read.All`, but creating one needs
`DeviceManagementConfiguration.ReadWrite.All`. The scope table in the script was read off the
Create documentation for exactly this reason rather than derived from the export's read scopes.

Microsoft moved the three script endpoints from `DeviceManagementConfiguration.*` to
`DeviceManagementScripts.ReadWrite.All` on 2025-07-31. Older documentation says otherwise.

Run `-TestPermissionOnly` first. It decodes the token and names every area *present in your
source folder* that it cannot create — areas with no folder are not worth a warning.

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
command line puts it in PSReadLine history and any active transcript.

## Certificate authentication

A certificate is preferred over a client secret and, when one is resolved, always wins over a
secret left in the environment — nothing has to be unset by hand.

The certificate is created and uploaded exactly as for the export; see that script's README for
the `openssl` and `New-SelfSignedCertificate` commands. Upload the `.cer` to the target
tenant's app registration under **Certificates & secrets**; the private key never leaves
wherever it was generated.

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

### Several customers

`-CustomerConfigPath` reads credentials from a local JSON file instead of the environment.
`-CustomerName` picks one without prompting; leaving it out prompts — a native picker on macOS,
a numbered console menu elsewhere.

**It is the same file, the same field names and the same four precedence rules as the export**,
so one `customers.json` serves both scripts. Use the export's `customers.sample.json` as the
template.

```powershell
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import `
    -CustomerConfigPath ~/.intune/customers.json -CustomerName 'Fabrikam AB' -WhatIf
```

What differs from the export is what the selection *means*: there it names the tenant being
read, here it names the tenant being **written to**. Nothing checks that the target is the
tenant the source data came from — importing customer A's configuration into customer B is the
entire point of the script, so the run banner makes both sides visible instead:

```
Source : /Users/you/Import
         (export 2026-08-20T09:14:00, Contoso AB / 1111-…)
Target : Fabrikam AB  (4444-…)   WRITE
Areas  : 14 folder(s), 18 file(s)
```

The source line is filled in from the export's `_manifest_*.json` if one is sitting in the
source folder, and costs no extra Graph call. Without a manifest it shows the path alone.

**`-SourceDirectory` is deliberately not readable from the customer file**, unlike the export's
`outputDirectory`. It is the data being imported, not a property of the target tenant, and
letting a customer entry supply it would make "which folder am I about to push into this
tenant" depend on which customer was picked.

Add the filled-in copy to `.gitignore`, and `chmod 600` it — the script warns if it is readable
beyond its owner.

## Usage

The order matters. Each step is cheap and rules out the failure the next one would hit.

```powershell
# 1. Unpack the export's sidecar archive first - run folders from 1.12.0 and later
#    keep the area folders inside the zip
Expand-Archive -Path './Contoso-AB_2026-08-20_0914_sidecars.zip' -DestinationPath ~/Import

# 2. Permission check. Reads nothing, writes nothing, posts nothing
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -TestPermissionOnly

# 3. Dry run. Contacts Graph only to read existing names; writes the report with whatIf: true
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -WhatIf -Verbose

# 4. For real, one area at a time
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -Area 'Assignment-Filter'

# 5. The rest, once the first area looks right in the portal
./Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -Verbose
```

A real run prints the banner and asks once for confirmation before the first write. `-Force`
skips the prompt, which is what a scheduled run needs; a non-interactive session with no
`-Force` warns that the prompt was skipped rather than blocking on a `Read-Host` nobody will
answer.

`-ReportDirectory` moves the report somewhere other than the source folder. Use it when the
source sits in OneDrive or Dropbox — see [Data sensitivity](#data-sensitivity).

## Output

Two things: the result objects on the pipeline, and `_importreport_<stamp>.json` written into
the source folder next to the data it describes — the same place and the same `_` prefix
convention the export uses for its `_manifest_`. Loose `_`-prefixed files in the source root
are skipped by the "files in the root were ignored" warning, so a second run does not complain
about the first run's report.

```
Import/
  _manifest_2026-08-20_0914.json          ← the export's, if you kept it
  _importreport_2026-09-01_1204.json      ← this script's
  Settings-Catalog/
  Compliance-Policy/
```

The file name uses local time so a run is easy to identify while browsing; the report records
the same instant in UTC, in local time, and with the offset.

```json
{
  "schemaVersion": 1,
  "runTimestampUtc": "2026-09-01T10:04:54.0274400Z",
  "runTimestampLocal": "2026-09-01T12:04:54",
  "utcOffset": "02:00:00",
  "timeZone": "Europe/Stockholm",
  "scriptVersion": "1.1.0",
  "whatIf": true,
  "targetTenantId": "4444-…",
  "targetCustomerName": "Fabrikam AB",
  "sourceDirectory": "/Users/you/Import",
  "sourceTenantId": "1111-…",
  "sourceTenantName": "Contoso AB",
  "sourceRun": "2026-08-20T09:14:00",
  "areasSelected": "",
  "runComplete": true,
  "abortReason": "",
  "totals": { "created": 0, "duplicate": 0, "invalid": 1, "failed": 0,
              "whatif": 2, "unsupported": 1, "unknownArea": 1, "blocked": 0 },
  "results": [
    { "area": "Settings-Catalog", "file": "a.json", "name": "SC test",
      "status": "whatif", "detail": "deviceManagement/configurationPolicies",
      "createdId": "" }
  ]
}
```

`totals` is built from a fixed key list, not from `Group-Object`. A status that did not occur
reads as `0` rather than being absent, because "no rows" and "did not happen" are different
states and both have to be legible without interpreting the warning stream.

`runComplete` and `abortReason` are what tell an aborted run from a finished one. `detail`
carries the reason a row got the status it has — for a failure, Graph's own `code` and
`message`. `createdId` is its own field so `detail` never has to be both.

| `status` | Meaning |
|---|---|
| `created` | Posted successfully; `createdId` holds the new object's id |
| `duplicate` | A policy with that name already exists in the target tenant |
| `invalid` | The sidecar cannot produce a valid body; nothing was posted |
| `failed` | Graph rejected the POST; `detail` has the service's message |
| `whatif` | Would have been created |
| `unsupported` | The area cannot be created from a single POST |
| `unknown-area` | Folder name does not match a known export area |
| `blocked` | 403 on the area — the token lacks the scope; one row, not one per file |

## Error semantics

**403** means a missing scope for that one area. Intune names the scope it wants. The script
records one `blocked` row for the area and moves on to the next — not one row per file, since
every file in it would fail identically.

**401** is global: the token itself is not accepted. One automatic refresh covers a genuinely
stale token; a second 401 aborts the run. The report is still written, with
`runComplete: false`.

**401 with a generic message that names no scope** is not a permission problem at all. Graph
wraps an Intune-side rejection this way, and on a developer tenant it usually means an expired
Intune licence: Entra ID keeps working, `/groups` answers fine, and every `deviceManagement`
endpoint returns 401 no matter who asks. Check `GET /v1.0/subscribedSkus` before touching the
app registration.

**400** is the interesting one, and the reason `Get-GraphErrorDetail` exists. `Invoke-RestMethod`
puts the response body in `ErrorDetails.Message` and its own exception says only
`400 (Bad Request)`. The report gets the full thing:

```
Response status code does not indicate success: 400 (Bad Request). |
BadRequest: Property platforms has an invalid value notAPlatform.
```

## Data sensitivity

The source folder holds the tenant's complete security configuration, including script bodies
and security baselines. Nothing here protects it.

The **import report** is its own item: it names the target tenant's ID and every policy name
that was created. That is the same sensitivity class as the export's output. It lands in the
source folder by default; use `-ReportDirectory` to put it somewhere else if the source folder
is synchronised to OneDrive or Dropbox.

## On the code itself

This was written with heavy AI assistance, over days rather than a long slow burn. Worth saying
plainly rather than leaving to be discovered.

What it has going for it is that the bugs were found by **running it**, not by reading it:

- `Get-ExistingName` returned its `HashSet` without a comma guard. PowerShell enumerates a
  collection on the way out of a function, so an empty set came back as `$null` and a
  one-element set as a bare string — and a string's `.Contains()` does substring matching, so
  a policy named `Windows` would have matched `Windows 11 Baseline` and been skipped as a
  duplicate. Both failures are silent.
- Exports before 1.11.0 wrote `settings` as `[[{...}]]`, one array too deep. Posting that
  creates a Settings Catalog policy with no settings at all and returns 201. The detection is
  shape-based rather than version-based so it keeps working once every run folder has been
  regenerated.
- The export's `Invoke-GraphRequest` treats a status of `0` — no response, network error,
  timeout — as retryable. Correct for a `GET`, dangerous for a `POST`; see
  [The hard requirement](#the-hard-requirement).
- Copying the export's 401 handler verbatim would have looked right and done nothing. It nulls
  a single `$script:TokenCache`; this script caches the token and its expiry in two fields, and
  clearing only the token hands the same rejected token straight back on the retry.

Judge it on the behaviour, not the provenance. It is not certified, warrantied or supported —
and unlike the export, which only ever issues `GET`, this one writes. Read it before running it
against a tenant you care about, and start with `-TestPermissionOnly` and `-WhatIf`.

## Known limitations

- **Five areas cannot be imported.** They are reported with the reason when their folder is
  present, rather than silently ignored:

  | Area | Why |
  |---|---|
  | `Group-Policy-Configuration-ADMX` | Needs the container created first, then one `definitionValue` per setting |
  | `Endpoint-Security-Intent` | Bound to a template ID that is not portable between tenants |
  | `Enrollment-Configuration` | Largely tenant singletons that can be edited but not created |
  | `App-Configuration-Managed-Devices` | References app IDs that do not exist in the target tenant |
  | `Application` | Needs content upload, not a JSON body |

- **The three script areas are not importable yet, and that is the export's gap.** The
  collection GET returns an empty `scriptContent` / `detectionScriptContent`, and those areas
  have no `DetailResourceFormat` in the export's `$policyDefinitions`, so nothing ever fetches
  the bodies. The import rejects such files as `invalid`, which is the right behaviour — a
  remediation script with no script in it is not worth creating. The fix belongs in the export.
- **A compliance policy may get an injected `scheduledActionsForRule`.** Graph refuses to
  create one without at least one scheduled action. `scheduledActionsForRule` is a navigation
  property, so a plain collection GET omits it; the export asks for it with `$expand`, so a
  current sidecar carries it. Older sidecars, and any run where the expanded query failed and
  the export fell back to a flat one, do not — and for those the import injects **block after
  0 hours** and warns. **Review the grace period in the portal afterwards.**
- **Area folders live in a zip** in export run folders from 1.12.0 onwards. Unpack first. The
  script says so if it finds no area folders, but it cannot read the archive itself yet.
- **Everything is created unassigned.** Assignments are never imported.
- **The duplicate check is name-based.** An object renamed in the target tenant is not
  recognised and gets created a second time.
- **No updates.** Creation only. A name that already exists is skipped, never patched — there
  is no `PATCH` path and no rollback.
- **Beta endpoints throughout.** Required for remediations, shell scripts and driver update
  profiles. Beta can change without notice.
- **Shared authentication code has drifted.** `Get-ClientCertificate` exists in three files —
  this one, the export and `New-IntuneWin32AppJson.ps1` — in three different versions, and
  `ConvertTo-Base64Url` and `New-ClientAssertion` in two. Do not "resynchronise" them by
  pasting one copy over another; the win32 copy takes a `[string]` password and catches only
  `PlatformNotSupportedException`, which the export widened deliberately.

## License

MIT.
