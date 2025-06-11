[cmdletbinding()]
Param([bool]$verbose)
$VerbosePreference = if ($verbose) { 'Continue' } else { 'SilentlyContinue' }

function ConvertTo-SystemEventMessage ($eventDetail) {
    # https://learn.microsoft.com/en-us/graph/system-messages#supported-system-message-events
    switch ($eventDetail."@odata.type") {
        "#microsoft.graph.callEndedEventMessageDetail" {
            "Call ended after $($eventDetail.callDuration)."
            Break
        }
        "#microsoft.graph.callStartedEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) started a call."
            Break
        }
        "#microsoft.graph.chatRenamedEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) changed the chat name to $($eventDetail.chatDisplayName)."
            Break
        }
        "#microsoft.graph.membersAddedEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) added $(($eventDetail.members | ForEach-Object { Get-DisplayName $_.id }) -join ", ")."

            Break
        }
        "#microsoft.graph.membersDeletedEventMessageDetail" {
            if (
                ($eventDetail.members.count -eq 1) -and
                ($null -ne $eventDetail.initiator.user) -and
                ($eventDetail.initiator.user.id -eq $eventDetail.members[0].id)
            ) {
                "$(Get-DisplayName $eventDetail.members[0].id ) left."
            }
            else {
                "$(Get-Initiator $eventDetail.initiator) removed $(($eventDetail.members | ForEach-Object { Get-DisplayName $_.id }) -join ", ")."
            }
            
            Break
        }
        "#microsoft.graph.messagePinnedEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) pinned a message."
            Break
        }
        "#microsoft.graph.messageUnpinnedEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) unpinned a message."
        }
        "#microsoft.graph.teamsAppInstalledEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) added $($eventDetail.teamsAppDisplayName) here."
        }
        "#microsoft.graph.teamsAppRemovedEventMessageDetail" {
            "$(Get-Initiator $eventDetail.initiator) removed $($eventDetail.teamsAppDisplayName)."
        }
        Default {
            Write-Warning "Unhandled system event type: $($eventDetail."@odata.type")"
            "Unhandled system event type $($eventDetail."@odata.type"): $($eventDetail | ConvertTo-Json -Depth 5)"
        }
    }
}
