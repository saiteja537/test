Your `config.json` is correct now. The screenshot shows `"Environment": "UAT"`, so the script is reading that setting or defaulting to UAT instead of letting you select PROD.

## Fix the environment selection

In `sap-bo-user-management.ps1`, find the code that loads the environment from the configuration. It may look similar to:

```
$environment = $config.Environment
$environmentConfig = $config.Environments.$environment
```

Replace that part with this interactive selection:

```
Write-Host ""
Write-Host "Select SAP BusinessObjects environment:" -ForegroundColor Cyan
Write-Host "1. LOCAL"
Write-Host "2. UAT"
Write-Host "3. PROD" -ForegroundColor Yellow

$choice = Read-Host "Enter 1, 2, or 3"

switch ($choice) {
    "1" { $environment = "LOCAL" }
    "2" { $environment = "UAT" }
    "3" {
        if (-not $config.AllowProductionDeletion) {
            Write-Host "Production operations are disabled in config.json." -ForegroundColor Red
            exit 1
        }
        $environment = "PROD"
    }
    default {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        exit 1
    }
}

$environmentConfig = $config.Environments.PSObject.Properties[$environment].Value

if ($null -eq $environmentConfig) {
    throw "Environment '$environment' is missing from config.json."
}

$restBaseUrl = $environmentConfig.RestBaseUrl
$cmcUrl = $environmentConfig.CmcUrl

Write-Host "Selected environment: $environment" -ForegroundColor Green
Write-Host "CMC URL: $cmcUrl"
Write-Host "REST URL: $restBaseUrl"
```

### Important

Your current configuration has:

```
"AllowProductionDeletion": false
```

That deliberately blocks the PROD option in the code above. Keep it disabled until production deletion is approved and tested. Also, make sure you replace the existing environment-selection block rather than adding this block alongside it; otherwise the old UAT assignment may override your selection.

Save the script and run it again. Choose `2` for UAT or `3` for PROD once production operations are authorized.
