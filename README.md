# test
test
The error is clear from your screenshot:

`FATAL ERROR: The property 'UAT' cannot be found on this object.`

Your `config.json` contains `"Environment": "UAT"`, but the `Environments` object shown in the screenshot contains only `LOCAL` and `PROD`. The script is trying to retrieve an environment entry that doesn't exist.

## Fix your `config.json`

Replace the configuration with this structure, retaining the correct URLs:

```
{
  "Environment": "UAT",
  "Environments": {
    "LOCAL": {
      "RestBaseUrl": "http://localhost:8080/biprws",
      "CmcUrl": "http://localhost:8080/BOE/CMC"
    },
    "UAT": {
      "RestBaseUrl": "https://gfsbi4newuat.capgemini.com/biprws",
      "CmcUrl": "https://gfsbi4newuat.capgemini.com/BOE/CMC"
    },
    "PROD": {
      "RestBaseUrl": "https://gfsbi4.capgemini.com/biprws",
      "CmcUrl": "https://gfsbi4.capgemini.com/BOE/CMC"
    }
  },
  "Authentication": "secWinAD",
  "AdminUsername": "GFTEST2",
  "PageSize": 100,
  "RequestTimeoutSeconds": 60,
  "ProtectedUsernames": [
    "Administrator",
    "Guest",
    "SMAdmin"
  ],
  "RequireConfirmation": true,
  "VerifyDeletion": true,
  "AllowProductionDeletion": false,
  "LogFile": ".\\user-management.log"
}
```

## Validate and run

From the directory containing both files, run:

```
$config = Get-Content .\config.json -Raw | ConvertFrom-Json
$config.Environments.PSObject.Properties.Name
```

You should see `LOCAL`, `UAT`, and `PROD`.

Then run:

```
.\sap-bo-user-management.ps1
```

Important: This fixes the missing UAT configuration entry. Keep `Environment` set to `UAT` while testing. Your current production URL is configured, but production deletion should remain disabled until UAT testing and the required change approval are complete.
