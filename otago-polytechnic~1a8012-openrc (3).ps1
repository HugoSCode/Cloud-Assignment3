Param (
    [switch]$notoken,
    [switch]$n,
    [switch]$help,
    [switch]$h
);
if ($args) {
    Write-Warning "Unsupported option(s): $args"
    Get-Help
    Exit
}
###############
# Configuration
###############
#-------------------------------------------
# Configuration variables for Catalyst Cloud
#-------------------------------------------
# Set the authentication API and version.
$Env:OS_AUTH_URL = "https://api.nz-por-1.catalystcloud.io:5000/v3"
$Env:OS_IDENTITY_API_VERSION = "3"
# Set the domain name for authentication.
$Env:OS_USER_DOMAIN_NAME = "Default"
$Env:OS_PROJECT_DOMAIN_ID = "default"
# Set the user name.
$Env:OS_USERNAME = "smitht8@student.op.ac.nz"
# Set the project name and id (the name is sufficient if unique, but it is a
# best practice to set the id in case two projects with the same name exist).
$Env:OS_PROJECT_ID = "d60888a880d241138615cce95884f358"
$Env:OS_PROJECT_NAME = "otago-polytechnic~1a8012"
# Set the region name.
$Env:OS_REGION_NAME = "nz-por-1"
$Env:OS_STORAGE_URL = "https://object-storage.nz-por-1.catalystcloud.io:443/v1/AUTH_d60888a880d241138615cce95884f358"
# Blank variables can result in unexpected errors. Unset variables that were
# left empty.
If ($Env:OS_USER_DOMAIN_NAME.length -eq 0) { $Env:OS_USER_DOMAIN_NAME = $null }
If ($Env:OS_PROJECT_DOMAIN_ID.length -eq 0) { $Env:OS_PROJECT_DOMAIN_ID = $null }
If ($Env:OS_REGION_NAME.length -eq 0) { $Env:OS_REGION_NAME = $null }
If ($Env:OS_STORAGE_URL.length -eq 0) { $Env:OS_STORAGE_URL = $null }
# As a precaution, unset deprecated OpenStack auth v2.0 variables (in case they
# have been set by other scripts or applications running on the same host).
$Env:OS_TENANT_ID = $null
$Env:OS_TENANT_NAME = $null
###########
# Functions
###########
# Style text output as sucess message (green)
Function Output-Success {
    Param([string]$s);
    Write-Host $s -ForegroundColor Green
}
# Style text output as warning message (yellow)
Function Output-Warning {
    Param([string]$s);
    Write-Host $s -ForegroundColor Yellow
}
# Style text output as error message (red)
Function Output-Error {
    Param([string]$s);
    Write-Host $s -ForegroundColor Red
}
# Style text output as debug message (pink)
Function Output-Debug {
    Param([string]$s);
    Write-Host "DEBUG: $s" -BackgroundColor White -ForegroundColor Black
}
# Get a cloud token using the preferred method available  (openstack, Invoke-WebRequest)
function Get-CloudToken {
    # Clear previous access token stored in memory, if any (because it may have
    # expired).
    $Env:OS_AUTH_TYPE = $Null
    $Env:OS_TOKEN = $Null
    $Env:OS_AUTH_TOKEN = $Null
    try {
        # Use openstack client
        Get-Command openstack -ErrorAction Stop | Out-Null
        $Env:OS_TOKEN = openstack token issue -f value -c id
    } catch {
        # Use Invoke-WebRequest
        $data = @{
            "auth" = @{
                "identity" =  @{
                    "methods" = @("password");
                    "password" = @{
                        "user" = @{
                            "name" = $Env:OS_USERNAME;
                            "domain" = @{ "name" =  $Env:OS_USER_DOMAIN_NAME};
                            "password" = $Env:OS_PASSWORD;
                        }
                    }
                };
                "scope" = @{
                    "project" = @{
                        "id" = $Env:OS_PROJECT_ID
                    }
                }
            }
        } | ConvertTo-Json -Depth 5
        $url = "$Env:OS_AUTH_URL/auth/tokens"
        $headers = @{ "Content-Type" = "application/json" }
        $response = Invoke-WebRequest -Method 'POST' -Uri $url -Headers $headers -Body $data -UseBasicParsing
        $Env:OS_TOKEN = $response.Headers["X-Subject-Token"]
    }
}
# Parse command line arguments.
Function Parse-Arguments {
    # Reset variables before entering the parse loop, because they may have a
    # value set in the current shell session.
    $global:USE_TOKEN = $TRUE
    If (($help) -or ($h)) {
        Get-Help
        Exit
    }
    If (($notoken) -or ($n)) {
        Output-Warning "Warning: The --no-token option cannot be used with accounts that have MFA enabled. Ensure MFA is disabled before using this option."
        $global:USE_TOKEN = $FALSE
    }
}
# Set the MFA code, if enabled.
Function Prompt-MFAPasscode {
    $OS_MFACODE_INPUT = Read-Host "Please enter your MFA verification code (leave blank if not enabled)"
    If ($OS_MFACODE_INPUT.length -eq 0) {
        Output-Warning "MFA is recommended and can be enabled under the settings tab of the dashboard."
    } Else {
        $Env:OS_PASSWORD = "$Env:OS_PASSWORD$OS_MFACODE_INPUT"
    }
    $OS_MFACODE_INPUT = $null
}
# Prompt for password
Function Prompt-Password {
    $OS_PASSWORD_INPUT = Read-Host "Please enter the password for user $Env:OS_USERNAME" -AsSecureString
    $Env:OS_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($OS_PASSWORD_INPUT))
}
# Display help text / usage information
Function Get-Help {
    $name = (Get-Item $PSCommandPath ).Name
    Write-Output "Usage: . $name [-h] [-NoToken]"
    Write-Output ''
    Write-Output 'Optional arguments:'
    Write-Output '  -h, -help                Show this help text and exit.'
    Write-Output '  -n, -NoToken             Sets the $Env:OS_USERNAME and $Env:OS_PASSWORD'
    Write-Output '                           environment variables, but does not fetch'
    Write-Output '                           or store an auth token on $Env:OS_AUTH_TOKEN or'
    Write-Output '                           $Env:OS_TOKEN.'
}
# Helper Function to list openstack environment variables
Function Get-OpenstackEnv {
    Get-ChildItem Env: | Where-Object {$_.name -match "OS_"}
}
##########
# Main ()
##########
Parse-Arguments
#----------------------------------------------------
# Prompt for username and password for authentication
#----------------------------------------------------
Prompt-Password
# # Only prompt for MFA if user is using token based auth
if ($USE_TOKEN) {
    Prompt-MFAPasscode
    # Generate a new access token.
    Write-Output "Requesting a new access token..."
    Get-CloudToken
    If ($Env:OS_TOKEN.length -eq 0 ) {
        $Env:OS_TOKEN = $null
        Output-Error "Failed to authenticate. Credentials may be incorrect or auth API inaccessible."
    } Else {
        # Set the token variables, so the access token can be used multiple times
        # util it expires.
        $Env:OS_AUTH_TYPE = "token"
        $Env:OS_AUTH_TOKEN = $OS_TOKEN
        Output-Success 'Access token obtained successfully and stored in $OS_TOKEN.'
    }
    # Clear all variables that are no longer needed from memory.
    $Env:OS_PROJECT_NAME = $null
    $Env:OS_PROJECT_DOMAIN_NAME = $null
    $Env:OS_PROJECT_DOMAIN_ID = $null
    $Env:OS_USER_DOMAIN_NAME = $null
    $Env:OS_USER_DOMAIN_ID = $null
    $Env:OS_USERNAME = $null
    $Env:OS_PASSWORD = $null
} Else {
    $Env:OS_AUTH_TYPE = $null
    $Env:OS_TOKEN = $null
    $Env:OS_AUTH_TOKEN = $null
    Output-Success "Environment variables required for authentication are set."
    Write-Output "You can use the 'openstack token issue' command to obtain an auth token."
}