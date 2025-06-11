[cmdletbinding()]
Param([bool]$Verbose)
$VerbosePreference = if ($Verbose) { 'Continue' } else { 'SilentlyContinue' }

function ConvertTo-ChatName ($chat, $members, $me) {
    $name = $chat.topic

    if ($null -eq $chat.topic) {
        $memberNames = $members | ForEach-Object -Process {
            if ($null -eq $_.displayName) {
                Write-Verbose "No displayName for $($_.userId), fetching displayName. User data: $_"
                $_.displayName = (Get-DisplayName $_.userId)
            }

            $_
        } | Select-Object -ExpandProperty "displayName" | Select-Object -Unique | Sort-Object 
        $name = ($memberNames | Where-Object { $_ -notmatch $me.displayName }) -join ", "
    }

    $name
}
