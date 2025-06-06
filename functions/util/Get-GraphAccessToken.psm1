[cmdletbinding()]
Param([bool]$verbose)
$VerbosePreference = if ($verbose) { 'Continue' } else { 'SilentlyContinue' }
$ProgressPreference = "SilentlyContinue"

# $resourceScores = "Chat.Read User.Read offline_access"
# https://learn.microsoft.com/EN-US/azure/active-directory/develop/scopes-oidc#openid
# $openIdScopes = "offline_access openid"

Set-Variable -Name accessToken -Value $null -Scope Script
Set-Variable -Name expires -Value $null -Scope Script

function Get-TokenClaimsAndSetExpires {
    param([string]$token)
    $tokenParts = $token -split '\.'
    if ($tokenParts.Length -ne 3) {
        Write-Warning "Token does not appear to be a valid JWT (expected 3 parts, got $($tokenParts.Length))."
        $script:expires = $null
        return
    }
    $header = $tokenParts[0]
    $payload = $tokenParts[1]
    $signature = $tokenParts[2]

    # Decode payload
    $payload = $payload.Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
    }
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        $exp = $($claims.exp)
        $epoch = [datetime]::SpecifyKind([datetime]'1970-01-01 00:00:00', [System.DateTimeKind]::Utc)
        $expiresLocal = $epoch.AddSeconds([int64]$exp)
        if ($expiresLocal -ge (((Get-Date).ToUniversalTime() + [TimeSpan]::FromMinutes(5)))) {
            return @{ Token = $token; Expires = $expiresLocal }
        } else {
            Write-Warning "Token is expiring soon."
        }
    } catch {
        Write-Warning "Could not parse token payload. Raw base64: $payload"
        Write-Warning "Error: $($_.Exception.Message)"
        $script:expires = $null
        $script:accessToken = $null
    }
    return @{ Token = ""; Expires = $null }
}



function Get-GraphAccessToken ($clientId, $tenantId) {
    while ([string]::IsNullOrEmpty($script:accessToken) -or $script:expires -le (((Get-Date).ToUniversalTime() + [TimeSpan]::FromMinutes(5)))) {
        $token = Read-Host "Paste your Access Token from https://developer.microsoft.com/en-us/graph/graph-explorer"
        $result = Get-TokenClaimsAndSetExpires $token
        $script:accessToken = $result.Token
        $script:expires = $result.Expires
    }
    $script:accessToken
}