#Requires -Version 5.1
<#

    .SYNOPSIS
        Exports Microsoft Chat History

    .DESCRIPTION
        This script reads the Microsoft Graph API and exports of chat history into HTML files in a location you specify.

    .PARAMETER exportFolder
        Export location of where the HTML files will be saved. For example, "D:\ExportedHTML\"

    .PARAMETER toExport
        If specified, only group chats this string (exact match) will be exported

    .PARAMETER avoidOverwrite
        If a chat with the same file name already exists, this will create the new file with a number at the end instead (such as (1))

    .EXAMPLE
        .\Get-MicrosoftTeamsChat.ps1 -exportFolder "D:\ExportedHTML" -skipIds '19:c968a252f5dc4310bd6714883389dcfe@thread.v2'

    .NOTES
        Original Author: Trent Steenholdt
        Pre-requisites: An app registration with delegated User.Read, Chat.Read and User.ReadBasic. All permissions is needed in the Azure AD tenant you're connecting to.

#>

[cmdletbinding()]
Param(
    [Parameter(Mandatory = $false, HelpMessage = "Export location of where the HTML files will be saved.")] [string] $exportFolder = "out",
    [Parameter(Mandatory = $false, HelpMessage = "If specified, only chats named (exact match) will be exported")] [string[]] $toExport = $null,
    [Parameter(Mandatory = $false, HelpMessage = "Any chat IDs specified will be skipped")] [string[]] $skipIds = @(),
    [Parameter(Mandatory = $false, HelpMessage = "If a chat with the same file name already exists, this will create the new file with a number at the end instead (such as (1))")] [switch] $avoidOverwrite
)

#################################
##   Import Modules  ##
#################################

Set-Location $PSScriptRoot

$verbose = $PSBoundParameters["verbose"]

Get-ChildItem "$PSScriptRoot/functions/chat/*.psm1" | ForEach-Object { Import-Module $_.FullName -Force -ArgumentList $verbose }
Get-ChildItem "$PSScriptRoot/functions/message/*.psm1" | ForEach-Object { Import-Module $_.FullName -Force -ArgumentList $verbose }
Get-ChildItem "$PSScriptRoot/functions/user/*.psm1" | ForEach-Object { Import-Module $_.FullName -Force -ArgumentList $verbose }
Get-ChildItem "$PSScriptRoot/functions/util/*.psm1" | ForEach-Object { Import-Module $_.FullName -Force -Global -ArgumentList $verbose }

####################################
##   HTML  ##
####################################

$chatHTMLTemplate = Get-Content -Raw ./assets/chat.html
$messageHTMLTemplate = Get-Content -Raw ./assets/message.html
$stylesheetCSS = Get-Content -Raw ./assets/stylesheet.css

#Script
$start = Get-Date

Write-Host -ForegroundColor Cyan "Starting script..."

$assetsFolder = Join-Path -Path $exportFolder -ChildPath "assets"
if (-not(Test-Path -Path $assetsFolder)) { New-Item -ItemType Directory -Path $assetsFolder | Out-Null }
$exportFolder = (Resolve-Path -Path $exportFolder).ToString()

Write-Host "Your chats will be exported to $exportFolder."

$me = Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/me" -Headers @{
    "Authorization" = "Bearer $(Get-GraphAccessToken)"
}

Write-Host ("Getting all chats, please wait... This may take some time.")
$chats = Get-Chats
Write-Host ("" + $chats.count + " possible chat chats found.")

$chatIndex = 0

foreach ($chat in $chats) {
    Write-Progress -Activity "Exporting Chats" -Status "Chat $($chatIndex) of $($chats.count)" -PercentComplete $(($chatIndex / $chats.count) * 100)
    $chatIndex += 1
    
    Write-Verbose "Exporting $($chat.id)"

    $members = Get-Members $chat
    $name = ConvertTo-ChatName $chat $members $me
    
    
    if ($null -ne $toExport -and $toExport -notcontains $name) {
        Write-Host ("$name is not in chats to export ($($toExport -join ", ")), skipping...")
        continue
    }

    if ($skipIds -contains $chat.id) {
        Write-Host ("$name ($($chat.id)) is in the skip list, skipping...")
        continue
    }

    $messages = Get-Messages $chat

    $messagesHTML = $null

    if (($messages.count -gt 0) -and (-not([string]::isNullorEmpty($name)))) {

        Write-Host -ForegroundColor White ("`r`n$name :: $($messages.count) messages.")

        # download profile pictures for use later
        if ($members.Count -le 10) {
            Write-Host "Downloading profile pictures..."
            foreach ($member in $members) {
                Get-ProfilePicture $member.userId $assetsFolder | Out-Null
            }
        } else {
            Write-Host "Skipping profile picture download (more than 10 members)..."
        }

        Write-Host "Processing messages..."

        foreach ($message in $messages) {
            $profilePicture = Get-ProfilePicture $message.from.user.id $assetsFolder
            $time = ConvertTo-CleanDateTime $message.createdDateTime

            switch ($message.messageType) {
                "message" {
                    $messageBody = $message.body.content

                    $imageTagMatches = [Regex]::Matches($messageBody, "<img.+?src=[\`"']https:\/\/graph.microsoft.com(.+?)[\`"'].*?>")

                    foreach ($imageTagMatch in $imageTagMatches) {
                        Write-Verbose "Downloading embedded image in message..."
                        $imagePath = Get-Image $imageTagMatch $assetsFolder
                        $messageBody = $messageBody.Replace($imageTagMatch.Groups[0], "<img src=`"$imagePath`" style=`"width: 100%;`" >")
                    }
        
                    $messageHTML = $messageHTMLTemplate
                    $messageHTML = $messageHTML.Replace("###ATTACHMENTS###", (ConvertTo-HTMLAttachments $message.attachments))
                    $messageHTML = $messageHTML.Replace("###CONVERSATION###", $messageBody)
                    $messageHTML = $messageHTML.Replace("###DATE###", $time)
                    $messageHTML = $messageHTML.Replace("###DELETED###", "$($null -ne $message.deletedDateTime)".ToLower())
                    $messageHTML = $messageHTML.Replace("###EDITED###", "$($null -ne $message.lastEditedDateTime)".ToLower())
                    $messageHTML = $messageHTML.Replace("###IMAGE###", $profilePicture)
                    $messageHTML = $messageHTML.Replace("###ME###", "$($message.from.user.displayName -eq $me.displayName)".ToLower())
                    $messageHTML = $messageHTML.Replace("###NAME###", (Get-Initiator $message.from clientId $tenantId))
                    $messageHTML = $messageHTML.Replace("###PRIORITY###", $message.importance)

                    $messagesHTML += $messageHTML
                        
                    Break
                }
                "systemEventMessage" {
                    $messageHTML = $messageHTMLTemplate
                    $messageHTML = $messageHTML.Replace("###ATTACHMENTS###", $null)
                    $messageHTML = $messageHTML.Replace("###CONVERSATION###", (ConvertTo-SystemEventMessage $message.eventDetail))
                    $messageHTML = $messageHTML.Replace("###DATE###", $time)
                    $messageHTML = $messageHTML.Replace("###DELETED###", $null)
                    $messageHTML = $messageHTML.Replace("###EDITED###", $null)
                    $messageHTML = $messageHTML.Replace("###IMAGE###", $profilePicture)
                    $messageHTML = $messageHTML.Replace("###ME###", "false")
                    $messageHTML = $messageHTML.Replace("###NAME###", "System Event")
                    $messageHTML = $messageHTML.Replace("###PRIORITY###", $message.importance)

                    $messagesHTML += $messageHTML

                    Break
                }
                Default {
                    Write-Warning "Unhandled message type: $($message.messageType)"
                }
            }
        }

        $chatHTML = $chatHTMLTemplate
        $chatHTML = $chatHTML.Replace("###MESSAGES###", $messagesHTML)
        $chatHTML = $chatHTML.Replace("###CHATNAME###", $name)
        $chatHTML = $chatHTML.Replace("###STYLE###", $stylesheetCSS)

        $name = $name.Split([IO.Path]::GetInvalidFileNameChars()) -join "_"

        if ($name.length -gt 64) {
            $name = $name.Substring(0, 64)
        }

        $file = Join-Path -Path $exportFolder -ChildPath "$name.html"

        if ($chat.chatType -ne "oneOnOne") {
            Write-Verbose "Chat is not oneOnOne, appending hash to end"
            # add hash of chatId in case multiple chats have the same name or members
            $chatIdStream = [IO.MemoryStream]::new([byte[]][char[]]$chat.id)
            $chatIdShortHash = (Get-FileHash -InputStream $chatIdStream -Algorithm SHA256).Hash.Substring(0,8)
            $file = $file.Replace(".html", ( " ($chatIdShortHash).html"))
        }

        if ($avoidOverwrite -eq $true) {
            Write-Verbose "Avoid overwrite enabled, appending counter if file path is not unique"
            $uniqueFile = $file
            $counter = 1

            while (Test-Path $uniqueFile) {
                $uniqueFile = $file.Replace(".html", ( " ($counter).html"))
                $counter++
            }

            $file = $uniqueFile
        }

        Write-Host -ForegroundColor Green "Exporting $file..."
        $chatHTML | Out-File -LiteralPath $file
    }
    else {
        Write-Host ("`r`n$name :: No messages found.")
        Write-Host -ForegroundColor Yellow "Skipping..."
    }
}

Write-Host -ForegroundColor Cyan "`r`nScript completed after $(((Get-Date) - $start).TotalSeconds)s... Bye!"