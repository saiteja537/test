
#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
#                  USERS DELETION
#          SAP BUSINESSOBJECTS AUTOMATION
# ============================================================

$script:Config = $null
$script:EnvironmentConfig = $null
$script:Headers = $null
$script:Token = $null
$script:LogPath = $null

function Show-Banner {
    $banner = @'
+------------------------------------------------------+
|                  USERS DELETION                      |
|          SAP BUSINESSOBJECTS AUTOMATION              |
+------------------------------------------------------+
| Developed by : Sai Teja Guddanti                     |
| Focus        : BO Administration & Automation        |
|                                                      |
| Questions, feedback, or bug reports are welcome.     |
| Contributions and suggestions are welcome.           |
|                                                      |
| Email        : saitejaguddanti999@gmail.com          |
| X            : x.com/SaiTejaGuddanti                 |
| LinkedIn     : See developer profile                 |
+------------------------------------------------------+
'@

    Write-Host $banner -ForegroundColor Cyan
    Write-Host ""
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "SUCCESS", "ERROR", "WARN")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] [{2}] {3}" -f `
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        $script:Config.Environment,
        $Level,
        $Message

    Add-Content -LiteralPath $script:LogPath `
        -Value $line -Encoding UTF8

    switch ($Level) {
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
        "WARN"    { Write-Host $Message -ForegroundColor Yellow }
        default   { Write-Host $Message -ForegroundColor Cyan }
    }
}

function Get-ApiUrl {
    param([Parameter(Mandatory)][string]$Path)

    return "$($script:EnvironmentConfig.RestBaseUrl.TrimEnd('/'))/$Path"
}

function Get-XmlAttr {
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Node,
        [Parameter(Mandatory)][string]$Name
    )

    $found = $Node.SelectSingleNode(
        ".//*[local-name()='attr' and @name='$Name']"
    )

    if ($found) {
        return $found.InnerText
    }

    return $null
}

function Invoke-BoRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "DELETE")]
        [string]$Method,
        [string]$Body
    )

    $params = @{
        Uri             = $Uri
        Method          = $Method
        Headers         = $script:Headers
        TimeoutSec      = [int]$script:Config.RequestTimeoutSeconds
        ErrorAction     = "Stop"
        UseBasicParsing = $true
    }
    if ($PSBoundParameters.ContainsKey("Body")) {
        $params.Body = $Body
        $params.ContentType = "application/xml"
    }

    try {
        return Invoke-WebRequest @params
    }
    catch {
        $message = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $message += " | Response: $($_.ErrorDetails.Message)"
        }
        try {
            if ($_.Exception.Response) {
                $message += " | HTTP status: $([int]$_.Exception.Response.StatusCode)"
            }
        } catch {}
        throw $message
    }
}

function Connect-Bo {
    $authType = [string]$script:Config.Authentication
    if ($authType -notin @("secEnterprise", "secWinAD")) {
        throw "Authentication must be secEnterprise or secWinAD."
    }

    $defaultUser = [string]$script:Config.AdminUsername
    $username = Read-Host "Username [$defaultUser]"
    if ([string]::IsNullOrWhiteSpace($username)) { $username = $defaultUser }

    $securePassword = Read-Host "Password" -AsSecureString
    if ($null -eq $securePassword) { throw "Password was not provided." }
    $password = [System.Net.NetworkCredential]::new("", $securePassword).Password
    if ([string]::IsNullOrWhiteSpace($password)) { throw "Password cannot be empty." }

    try {
        $escapedUser = [System.Security.SecurityElement]::Escape($username)
        $escapedPassword = [System.Security.SecurityElement]::Escape($password)
        $body = @"
<attrs xmlns="http://www.sap.com/rws/bip">
  <attr name="userName" type="string">$escapedUser</attr>
  <attr name="password" type="string">$escapedPassword</attr>
  <attr name="auth" type="string">$authType</attr>
</attrs>
"@
        $loginUri = Get-ApiUrl "logon/long"
        Write-Host "Connecting to BO REST Service using $authType..." -ForegroundColor Yellow
        $response = Invoke-WebRequest `
            -Uri $loginUri `
            -Method POST `
            -ContentType "application/xml" `
            -Headers @{ Accept = "application/xml" } `
            -Body $body `
            -TimeoutSec ([int]$script:Config.RequestTimeoutSeconds) `
            -UseBasicParsing `
            -ErrorAction Stop

        [xml]$xml = $response.Content
        $tokenNode = $xml.SelectSingleNode("//*[local-name()='attr' and @name='logonToken']")
        if (-not $tokenNode -or [string]::IsNullOrWhiteSpace($tokenNode.InnerText)) {
            throw "No logon token returned by SAP BO. Check endpoint, authentication type, and credentials."
        }

        $script:Token = $tokenNode.InnerText
        $script:Headers = @{
            "X-SAP-LogonToken" = '"' + $script:Token + '"'
            Accept = "application/atom+xml, application/xml"
        }
        Write-Log "Authentication successful using $authType. Logon token not displayed." "SUCCESS"
    }
    catch {
        throw "Login failed: $($_.Exception.Message)"
    }
    finally {
        $password = $null
        $escapedPassword = $null
        $body = $null
        $securePassword = $null
    }
}

function Get-AllBoUsers {
    $users = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $pageSize = [int]$script:Config.PageSize

    while ($true) {
        $uri = Get-ApiUrl "v1/users?page=$page&pagesize=$pageSize"
        $response = Invoke-BoRequest -Uri $uri -Method GET

        [xml]$xml = $response.Content

        $entries = @(
            $xml.SelectNodes(
                "/*[local-name()='feed']/*[local-name()='entry']"
            )
        )

        foreach ($entry in $entries) {
            $name = Get-XmlAttr -Node $entry -Name "name"
            $id = Get-XmlAttr -Node $entry -Name "id"

            if ($name -and $id) {
                $users.Add([PSCustomObject]@{
                    Name = $name
                    Id   = $id
                })
            }
        }

        if ($entries.Count -lt $pageSize) {
            break
        }

        $page++

        if ($page -gt 10000) {
            throw "Pagination safety limit reached."
        }
    }

    return $users.ToArray()
}

function Find-ExactUser {
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][object[]]$Users
    )

    $matches = @(
        $Users | Where-Object { $_.Name -ceq $Username }
    )

    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    return $null
}

function Remove-BoUser {
    param(
        [Parameter(Mandatory)][object]$Account
    )

    $username = [string]$Account.Name
    $userId = [string]$Account.Id

    if (@($script:Config.ProtectedUsernames) -ccontains $username) {
        Write-Log "PROTECTED ACCOUNT: '$username'. Skipped." "WARN"
        return
    }

    try {
        $uri = Get-ApiUrl "v1/users/$userId"
        $response = Invoke-BoRequest -Uri $uri -Method DELETE

        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            Write-Log "Empty deletion response for '$username'; verify in CMC." "WARN"
            return
        }

        [xml]$result = $response.Content

        $status = $result.SelectSingleNode(
            "//*[local-name()='attr' and @name='status']"
        )

        if (-not $status -or $status.InnerText -cne "success") {
            Write-Log "SAP did not confirm deletion of '$username'." "ERROR"
            Write-Host $response.Content -ForegroundColor Red
            return
        }

        if ([bool]$script:Config.VerifyDeletion) {
            $updatedUsers = @(Get-AllBoUsers)

            $remaining = @(
                $updatedUsers | Where-Object {
                    $_.Name -ceq $username -and $_.Id -eq $userId
                }
            )

            if ($remaining.Count -gt 0) {
                Write-Log "Deletion not verified: '$username' still exists." "ERROR"
                return
            }
        }

        Write-Log "SUCCESS: '$username' (ID $userId) deleted and verified." "SUCCESS"
    }
    catch {
        Write-Log "DELETE FAILED for '$username': $_" "ERROR"
    }
}

function Read-Targets {
    Write-Host "`nSelect mode:" -ForegroundColor Cyan
    Write-Host "1. Single user"
    Write-Host "2. Multiple users from TXT file"

    $mode = Read-Host "Enter 1 or 2"

    if ($mode -ceq "1") {
        $username = (Read-Host "Enter exact username").Trim()

        if ([string]::IsNullOrWhiteSpace($username)) {
            throw "Username cannot be empty."
        }

        return @($username)
    }

    if ($mode -ceq "2") {
        $filePath = (Read-Host "Enter full TXT file path").Trim().Trim('"')

        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "TXT file not found: $filePath"
        }

        $targets = @(
            Get-Content -LiteralPath $filePath |
                ForEach-Object { $_.Trim() } |
                Where-Object {
                    $_ -and -not $_.StartsWith("#")
                } |
                Select-Object -Unique
        )

        if ($targets.Count -eq 0) {
            Write-Host "USER LIST EMPTY: No usernames found in the TXT file." `
                -ForegroundColor Red
            return @()
        }

        return $targets
    }

    throw "Invalid selection. Enter 1 or 2."
}

function Confirm-DeletionBatch {
    param(
        [Parameter(Mandatory)][object[]]$Accounts
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "                     WARNING" -ForegroundColor Red
    Write-Host "               PERMANENT USER DELETION" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "Selected accounts will be deleted automatically." -ForegroundColor Red
    Write-Host "Deletion may be irreversible and accounts may not be recoverable." -ForegroundColor Red
    Write-Host ""
    Write-Host "Accounts selected: $($Accounts.Count)" -ForegroundColor Yellow

    foreach ($account in $Accounts) {
        Write-Host "  $($account.Name) (ID $($account.Id))" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "1: Yes - confirm deletion of the listed accounts" -ForegroundColor Yellow
    Write-Host "2: No  - cancel without deleting" -ForegroundColor Green

    return ((Read-Host "Enter 1 or 2") -ceq "1")
}

function Invoke-Main {
    Show-Banner

    $configPath = Join-Path $PSScriptRoot "config.json"

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Configuration file not found: $configPath"
    }

    $script:Config = Get-Content -LiteralPath $configPath -Raw |
        ConvertFrom-Json

    foreach ($key in @(
        "Environment", "Environments", "Authentication",
        "AdminUsername", "PageSize", "RequestTimeoutSeconds",
        "ProtectedUsernames", "VerifyDeletion", "LogFile"
    )) {
        if ($null -eq $script:Config.$key) {
            throw "Missing configuration property: $key"
        }
    }

    # Choose the target environment at runtime. The config value is only the default.
    $defaultEnvironment = [string]$script:Config.Environment
    $environmentNames = @($script:Config.Environments.PSObject.Properties.Name)

    Write-Host "Select SAP BusinessObjects environment:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $environmentNames.Count; $i++) {
        $name = $environmentNames[$i]
        $suffix = if ($name -ceq $defaultEnvironment) { " (default)" } else { "" }
        Write-Host ("{0}. {1}{2}" -f ($i + 1), $name, $suffix)
    }

    $choice = (Read-Host "Enter the environment number").Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $environmentName = $defaultEnvironment
    }
    elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $environmentNames.Count) {
        $environmentName = $environmentNames[[int]$choice - 1]
    }
    else {
        throw "Invalid environment selection. No changes made."
    }

    $script:Config.Environment = $environmentName
    $script:EnvironmentConfig = $script:Config.Environments.PSObject.Properties[$environmentName].Value

    if (-not $script:EnvironmentConfig -or
        -not $script:EnvironmentConfig.RestBaseUrl -or
        -not $script:EnvironmentConfig.CmcUrl) {
        throw "Invalid or incomplete environment: $environmentName"
    }

    if ($environmentName -eq "PROD") {
        Write-Host "PRODUCTION ENVIRONMENT SELECTED" -ForegroundColor Red
        if (-not $script:Config.AllowProductionDeletion) {
            throw "Production deletion is disabled. Use UAT first; enable only after formal approval/change control."
        }
        if ((Read-Host "Type the exact text PROD DELETE ENABLED to continue") -cne "PROD DELETE ENABLED") {
            throw "Production confirmation did not match. No changes made."
        }
    }

    $apiUri = [uri]$script:EnvironmentConfig.RestBaseUrl

    if (-not $apiUri.IsAbsoluteUri -or
        $apiUri.Scheme -notin @("http", "https")) {
        throw "RestBaseUrl must be an absolute HTTP or HTTPS URL."
    }

    if ($apiUri.Scheme -eq "http") {
        Write-Host "WARNING: HTTP does not encrypt credentials in transit." `
            -ForegroundColor Red

        if ((Read-Host "Type YES to continue") -cne "YES") {
            Write-Host "Cancelled. No changes made." -ForegroundColor Green
            return
        }
    }

    if ([int]$script:Config.PageSize -lt 1 -or
        [int]$script:Config.PageSize -gt 1000) {
        throw "PageSize must be between 1 and 1000."
    }

    $script:LogPath = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot $script:Config.LogFile)
    )

    Write-Host "Environment: $environmentName" -ForegroundColor Cyan
    Write-Host "CMC URL: $($script:EnvironmentConfig.CmcUrl)"
    Write-Host "REST URL: $($script:EnvironmentConfig.RestBaseUrl)"
    Write-Host "Authentication: $($script:Config.Authentication)"

    Connect-Bo

    $targets = @(Read-Targets)

    if ($targets.Count -eq 0) {
        return
    }

    # Resolve every requested name before authorizing any deletion.
    $allUsers = @(Get-AllBoUsers)
    $eligible = [System.Collections.Generic.List[object]]::new()
    $seenIds = @{}

    foreach ($target in $targets) {
        $account = Find-ExactUser -Username $target -Users $allUsers

        if (-not $account) {
            Write-Host ""
            Write-Host "============================================================" -ForegroundColor Red
            Write-Host " USER NOT FOUND: '$target'" -ForegroundColor Red
            Write-Host "============================================================" -ForegroundColor Red
            Write-Log "NOT FOUND: '$target'." "ERROR"
            continue
        }

        if (@($script:Config.ProtectedUsernames) -ccontains $account.Name) {
            Write-Log "PROTECTED ACCOUNT: '$($account.Name)'. Skipped." "WARN"
            continue
        }

        if (-not $seenIds.ContainsKey([string]$account.Id)) {
            $eligible.Add($account)
            $seenIds[[string]$account.Id] = $true
        }
    }

    if ($eligible.Count -eq 0) {
        Write-Host "`nNo eligible accounts to delete." -ForegroundColor Yellow
        return
    }

    if (-not (Confirm-DeletionBatch -Accounts $eligible.ToArray())) {
        Write-Host "`nCancelled. No users were deleted." -ForegroundColor Green
        Write-Log "Deletion batch cancelled by operator." "WARN"
        return
    }

    Write-Host "`nConfirmation accepted. Processing selected accounts..." `
        -ForegroundColor Yellow

    foreach ($account in $eligible) {
        Remove-BoUser -Account $account
    }

    Write-Host "`nProcessing complete. Review the log and verify results in CMC." `
        -ForegroundColor Cyan
}

try {
    Invoke-Main
}
catch {
    Write-Host "`nFATAL ERROR: $_" -ForegroundColor Red

    if ($script:LogPath) {
        try { Write-Log "FATAL ERROR: $_" "ERROR" } catch {}
    }
}
finally {
    $script:Headers = $null
    $script:Token = $null
}
