[cmdletbinding()]
Param([bool]$verbose)
$VerbosePreference = if ($verbose) { 'Continue' } else { 'SilentlyContinue' }

# used with eventDetail objects; member displayNames are sometimes null for no reason

function Get-DisplayName ($userId) {
    try {
        $user = Get-User $userId
        
        if ($null -ne $user.displayName) {
            $user.displayName
        }
        else {
            Write-Verbose "Fetched user's displayName is null."
            "Unknown ($userId)"
        }
    }
    catch {
        Write-Verbose "Failed to fetch a user's displayName."
        "Unknown ($userId)"
    }
}
