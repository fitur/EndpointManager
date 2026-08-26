# New-IntuneWin32AppJson.ps1

Takes a zip-packaged PSADT application and runs the entire path to a published Intune Win32
app in one command: extract, read metadata, parse the detection rule, build the Graph JSON,
upload, and assign to an Entra group.

Written to remove the manual clicking from a repetitive task. One command replaces roughly
fifteen minutes in the Intune portal, and — more importantly — removes the chance of a
mistyped detection rule or a forgotten disk requirement.

## What it does

1. Validates credentials and assignment input, before touching anything
2. Extracts the zip to a unique temporary directory next to it
3. Locates `ApplicationInformation.txt`, the `.intunewin` file and an optional `.png` icon
4. Reads the metadata and parses the detection rule (registry, MSI or file)
5. Builds a `win32LobApp` JSON artifact in Intune's own export format (UTF-16 LE)
6. Uploads the app, then corrects return code 1641 from `hardReboot` to `softReboot`
7. Assigns the app to an Entra group, optionally on a schedule

The JSON artifact is kept next to the zip file after a successful run, so it can be diffed,
archived or imported elsewhere.

## Requirements

**PowerShell 7.4 or later.** The script uses ternary operators, null-coalescing and
`ConvertFrom-Json -AsHashtable`, none of which exist in Windows PowerShell 5.1. Verified on
macOS and in Azure Functions.

**The [IntuneWin32App](https://github.com/MSEndpointMgr/IntuneWin32App) module** by
MSEndpointMgr handles the upload itself — encryption, Azure Storage chunking, content
versioning and commit. It is installed automatically on first run if missing. For
production use, pin it with `-IntuneWin32AppVersion` so a new release cannot change
behaviour unnoticed.

**An Entra ID app registration** authenticating with either a certificate (preferred) or a
client secret, and exactly one Graph permission:

| Permission | Type | Consent |
|---|---|---|
| `DeviceManagementApps.ReadWrite.All` | Application | Admin consent required |

Application, not Delegated — the client credentials flow does not work with delegated
permissions. No group permission is needed: the group ID is passed straight through to
Intune and never looked up in Entra.

A `403 Forbidden` during upload almost always means this permission is missing or
unconsented in that tenant. Authentication itself will still succeed, because a token is
issued regardless of what roles it carries.

## Input format

```
IgorPavlov_7Zip_26.02_Intune.zip
└── IgorPavlov_7Zip_26.02_Intune/
    ├── ApplicationInformation.txt
    ├── 7Zip_26.02.intunewin
    └── 7Zip.png                     ← optional
```

A `__MACOSX` folder, which macOS adds when zipping, is ignored. The files may also sit
directly in the zip root without a wrapping folder.

### ApplicationInformation.txt

Required fields:

```
Application - Vendor..: IgorPavlov
Application - Name....: 7Zip
Application - Version.: 26.02

Install command.......: Invoke-AppDeployToolkit.exe Install Silent
Uninstall command.....: Invoke-AppDeployToolkit.exe Uninstall Silent

DetectionMethod.(REG).: HKLM\Software\<COMPANY>\IgorPavlov 7Zip 26.02 x64 = Installed

Estimated Disk Space..: 15 MB
```

`Estimated Disk Space` is optional but recommended — when present it sets the disk
requirement in Intune, otherwise no requirement is applied. Anything missing is reported in
a single error listing every absent field, rather than one at a time.

The file may be UTF-8, UTF-16 (with or without BOM), Mac Roman or Windows-1252. The encoding
is detected automatically and any byte order mark is stripped, so `å ä ö` survive and the
first field in the file is read correctly regardless of whether the package was built on
macOS or Windows.

### Detection rules

The label may be `DetectionMethod.(REG)`, `.(MSI)` or `.(FILE)`:

```
HKEY_LOCAL_MACHINE\SOFTWARE\...\ClientState\{GUID}\pv >= 149.0.7827.54
HKLM\Software\<COMPANY>\IgorPavlov 7Zip 26.02 x64 = Installed
{D9275287-A12D-49AB-94DD-EC5AC30E95FC}
%ProgramFiles%\App\file.exe >= 1.2.3
```

Short hive names (`HKLM`, `HKCU`, `HKCR`, `HKU`, `HKCC`) are expanded automatically. Spaces
are handled in both the key path and the value name. The `=` operator is treated as a
version comparison when the value looks like a version number, and as a string comparison
otherwise.

An unparseable rule aborts the run and prints the raw value alongside the supported formats,
so it is immediately clear what needs fixing in the text file.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `INTUNE_TENANT_ID` | Yes | Tenant ID |
| `INTUNE_CLIENT_ID` | Yes | App registration client ID |
| `INTUNE_CLIENT_SECRET` | Yes* | App registration secret. \*Not needed when a certificate is used |
| `INTUNE_ASSIGNMENT_GROUP_ID` | No | Entra group object ID. Without it, assignment is skipped entirely |
| `INTUNE_DESCRIPTIONS_PATH` | No | Path or URL to `IntuneAppDescriptions.json`. Defaults to the copy in this repo |
| `INTUNE_APP_OWNER` | No | Owner recorded on the app in Intune. Left empty if unset |
| `INTUNE_CERT_THUMBPRINT` | No | Certificate in the CurrentUser store, used instead of the secret |
| `INTUNE_CERT_PATH` | No | PFX file, for environments without a certificate store |
| `INTUNE_CERT_PASSWORD` | No | Password for the PFX file |

```powershell
$env:INTUNE_TENANT_ID           = "..."
$env:INTUNE_CLIENT_ID           = "..."
$env:INTUNE_CLIENT_SECRET       = "..."
$env:INTUNE_ASSIGNMENT_GROUP_ID = "..."
```

The three credential variables have matching parameters, but prefer the variables — a secret
passed on the command line ends up in shell history and transcript logs.

If you administer more than one tenant, `-CustomerConfigPath` replaces these variables
entirely. See [Working across several customers](#working-across-several-customers).

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-AppPath` | — | **Required.** Path to the zip file, absolute or relative |
| `-AssignmentGroupId` | env var | Entra group object ID |
| `-AssignmentIntent` | `required` | `required`, `available` or `uninstall` |
| `-AssignmentNotification` | `showAll` | `showAll`, `showReboot` or `hideAll` |
| `-PatchTuesday` | off | Available 00:00, deadline 12:00 on the next Patch Tuesday |
| `-AvailableTime` | — | Explicit availability time |
| `-DeadlineTime` | — | Explicit installation deadline |
| `-UseLocalTime` | `$true` | Interpret times in the device's local time rather than UTC |
| `-Architecture` | `x64` | `x64`, `x86`, `arm64`, `x64x86`, `AllWithARM64` |
| `-MinimumWindowsRelease` | `W11_21H2` | `W10_1607` through `W11_22H2` |
| `-DescriptionsPath` | GitHub URL | Path or URL to the descriptions file |
| `-IntuneWin32AppVersion` | — | Pins the module version |
| `-Owner` | env var | Owner recorded on the app in Intune |
| `-Supersede` | off | Marks earlier versions of the same app as superseded |
| `-SupersedenceType` | `Update` | `Update` installs over the old version, `Replace` uninstalls it first |
| `-CustomerConfigPath` | — | Local JSON file with credentials for several customers |
| `-CustomerName` | — | Selects a customer without prompting |
| `-CertificateThumbprint` | env var | Certificate in the CurrentUser store |
| `-CertificatePath` `-CertificatePassword` | env vars | PFX file instead of a store lookup |
| `-TenantID` `-ClientID` `-ClientSecret` | env vars | Avoid on the command line |
| `-Quiet` | off | Suppresses the per-chunk upload progress |
| `-WhatIf` | — | Dry run |

## Usage

```powershell
# Publish as required, immediately
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip"

# Schedule on the next Patch Tuesday
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip" -PatchTuesday

# Publish to Company Portal for users to install on demand
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip" -AssignmentIntent available

# Explicit window
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip" `
    -AvailableTime (Get-Date "2026-09-01 08:00") `
    -DeadlineTime  (Get-Date "2026-09-08 17:00")

# Supersede earlier versions of the same app
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip" -Supersede

# Pick a customer from a local credential file
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip" -CustomerConfigPath ~/.config/em/customers.json

# Dry run: validates everything and writes the JSON, without touching Intune
./New-IntuneWin32AppJson.ps1 -AppPath "./App_1.0_Intune.zip" -WhatIf
```

`-WhatIf` skips authentication entirely and leaves the extracted folder in place so the
generated JSON can be inspected. Worth running first on any new package.

### Scheduling

| Invocation | Result |
|---|---|
| No time parameters | Published immediately |
| `-PatchTuesday` | Available 00:00, deadline 12:00 on the next second Tuesday |
| `-AvailableTime` + `-DeadlineTime` | Your own window |

`-PatchTuesday` cannot be combined with explicit times, and no scheduling works with
`-AssignmentIntent available` — Intune rejects deadline and local time settings on available
assignments, so the script stops before uploading rather than leaving the app published
without its assignment. Both times are always set together,
because the IntuneWin32App module silently skips an assignment when a future availability
time has no accompanying deadline — the script catches that combination and fails loudly
instead.

If today happens to be a Patch Tuesday, the next month is used rather than the same day.

### Output

The script returns an object, so it composes into larger automation:

```powershell
$result = ./New-IntuneWin32AppJson.ps1 -AppPath "./App.zip"
$result.AppId
```

| Field | Contents |
|---|---|
| `DisplayName` | Name as published in Intune |
| `AppId` | Intune app ID, or `$null` under `-WhatIf` |
| `JsonPath` | Path to the generated JSON artifact |
| `DetectionType` | `RegistryDetection`, `ProductCodeDetection` or `FileSystemDetection` |
| `DescriptionFound` | Whether the app matched an entry in the descriptions file |
| `AssignedGroupId` | Set only once assignment actually succeeded |
| `SupersededApps` | The earlier versions that were marked superseded |

### Superseding earlier versions

`-Supersede` finds earlier versions already in Intune and marks them as superseded by the
upload. Matching is deliberately strict, because a false positive would mark an unrelated app
as superseded: a candidate qualifies only when its name is exactly `<base> <version>` for
either the resolved display name or the `<Vendor> <Name>` fallback, and its version parses
and is strictly lower than the one being uploaded.

Uploading `7-Zip 26.02` therefore supersedes `7-Zip 26.01` and `IgorPavlov 7Zip 25.00`,
while leaving `7-Zip 27.00`, `7-Zip Pro 26.01`, `My 7-Zip 26.01` and a plain `7-Zip` alone.
Both naming conventions are checked so apps uploaded before a `displayName` override existed
are still recognised.

`Update` installs over the earlier version; `Replace` uninstalls it first.

## Certificate authentication

A certificate is preferred over a client secret: the private key stays in the OS keystore
and never sits in a file or an environment variable. Upload the public `.cer` under
**Certificates & secrets → Certificates** on the app registration, import the PFX locally,
and point the script at its thumbprint.

```powershell
./New-IntuneWin32AppJson.ps1 -AppPath "./App.zip" -CertificateThumbprint "A1B2C3..."
```

The thumbprint is looked up in the CurrentUser store, which is the login Keychain on macOS
and the certificate store on Windows. Where no usable store exists — a Linux-based Azure
Function, or a container — use a PFX file instead:

```powershell
./New-IntuneWin32AppJson.ps1 -AppPath "./App.zip" -CertificatePath ./cert.pfx -CertificatePassword $pw
```

Both forms produce the same certificate object internally, so moving between them, or later
to a certificate fetched from Key Vault, changes only where the bytes come from.

A certificate takes precedence when both a certificate and a secret are available, so a
secret left in the environment cannot silently shadow it.

## Working across several customers

Instead of setting environment variables per tenant, point the script at a local JSON file
holding credentials for every customer. Without `-CustomerName` it asks which one to use —
a native picker on macOS, a numbered menu elsewhere.

```powershell
./New-IntuneWin32AppJson.ps1 -AppPath "./App.zip" -CustomerConfigPath ~/.config/em/customers.json
./New-IntuneWin32AppJson.ps1 -AppPath "./App.zip" -CustomerConfigPath ~/.config/em/customers.json -CustomerName "Contoso"
```

`customers.sample.json` in this repo shows the format:

```json
{
    "customers": [
        {
            "name": "Contoso",
            "tenantId": "...",
            "clientId": "...",
            "certificateThumbprint": "A1B2C3...",
            "assignmentGroupId": "...",
            "appOwner": "Contoso IT"
        }
    ]
}
```

`name`, `tenantId` and `clientId` are required. For credentials, in order of preference:

| Keys | Notes |
|---|---|
| `certificateThumbprint` | Private key stays in the OS keystore. Best option |
| `certificatePath` + `certificatePassword` | PFX file, for hosts without a store |
| `secretVault` + `secretName` | Resolved through `Microsoft.PowerShell.SecretManagement` |
| `clientSecret` | Inline. Readable by any process running as you, whatever directory it sits in |

`assignmentGroupId`, `appOwner` and `descriptionsPath` are optional.

Two behaviours worth knowing:

**A value the customer does not define is cleared, not inherited.** If one customer has no
`assignmentGroupId` and your environment still holds another customer's, the app would
otherwise be assigned into the wrong tenant's group. The file is authoritative.

**Explicitly passed parameters still win**, so `-Owner` on the command line overrides
whatever the file says for that run.

The script warns if the file is readable by anyone but its owner. Run `chmod 600` on it and
add it to `.gitignore` — never commit a filled-in copy.

## App names and descriptions

`IntuneAppDescriptions.json`, next to the script, supplies the description shown in Company
Portal, and can
override the app name. Entries are matched against `Application - Name`, ignoring case and
punctuation, so `7Zip` matches `7-Zip`.

```json
"7Zip": {
    "displayName": "7-Zip",
    "description": "## 7-Zip\n\n..."
}
```

With `displayName` the app is named `7-Zip 26.02`. Without it, the name falls back to
`<Vendor> <Name> <Version>`, giving `IgorPavlov 7Zip 26.02`.

A plain string entry also works and is treated as description only, so older files keep
functioning.

Descriptions are written in Markdown. Adding a new base application means editing this file
alone — the script reads it from the repo by default, so the change applies everywhere at
once.

## On the code itself

This script was written with heavy AI assistance. That is worth saying plainly rather than
leaving it to be discovered.

What that means in practice is that the code was generated quickly and then earned its place
the slow way: three months of use against production tenants, every reported failure traced
to a root cause and fixed rather than worked around, and an independent review at the end
whose findings were verified individually before being applied — two of them turned out to
be wrong and were rejected with evidence.

Several fixes came from behaviour that only surfaces in real use, not from reading the code:

- The IntuneWin32App module appends its own default return codes to any supplied ones
  without deduplicating, producing duplicates in the portal. The script therefore omits
  `-ReturnCode` entirely and corrects 1641 with a separate PATCH afterwards.
- Omitting `-RequirementRule` makes the module fall back to Windows 10 20H2 and silently
  drop the disk requirement, so it is always supplied explicitly.
- `-WhatIf` propagates into filesystem operations inside called functions, which broke
  extraction until the local file operations were marked `-WhatIf:$false`.
- The return code patch and the group assignment both run after the app exists in Intune, so
  a failure in either warns rather than throws. Reporting them as fatal invited a rerun,
  which would create a duplicate app.

Judge it on the behaviour, not the provenance. It is not certified, warrantied or supported —
read it before running it against a tenant you care about, and use `-WhatIf` first.

## Known limitations

- **No duplicate check.** Running the same package twice creates two apps in Intune.
- **The app uploads immediately**, even when the assignment is scheduled. Only the
  assignment is deferred; the app is visible in the portal right away.
- **Patch Tuesday is calculated in the server's time zone** but interpreted in the device's,
  which can differ by a day for runs late in the evening under UTC.
- **One detection rule per app.** Multi-rule detection is not supported.
- **The customer file is read in clear text** unless you use a certificate or a secret
  vault. Treat it as a
  credential store: local only, `chmod 600`, never committed.
- **Supersedence relies on the naming convention.** Apps named outside `<base> <version>`
  are not found, and a version that does not parse as a version number is skipped rather
  than guessed at.

## License

MIT.