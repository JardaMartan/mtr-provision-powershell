# device configuration parameters
$deviceIP = "10.229.102.66"
$workspaceName = "PRG7-5-DeskPro 2"
$location = @{
    displayName = "PRG7";
    address1 = "Pujmanove 1753/10a";
    address2 = "";
    cityName = "Praha 4";
    zip = "14000";
    state = "";
    countryCode = "CZ";
    latitude = "50.0498981";
    longitude = "14.4352742";
    timeZone = "Europe/Prague";
}

# additional parameters
$timeZone = $location.timeZone
$timeFormat = "24H"
$dateFormat = "DD_MM_YY"
$language = "English"
$username = "admin"
$password = ""

$noProxyConfig = @(
"xConfiguration NetworkServices HTTP Proxy Mode: Off")

$pacProxyConfig = @(
"xConfiguration NetworkServices HTTP Proxy Mode: PACUrl",
"xConfiguration NetworkServices HTTP Proxy PACUrl: http://pac.proxy.com/pac.pac")

$manualProxyConfig = @(
"xConfiguration NetworkServices HTTP Proxy Mode: Manual",
"xConfiguration NetworkServices HTTP Proxy Url: proxy.esl.cisco.com:8080")

$wpadProxyConfig = @(
"xConfiguration NetworkServices HTTP Proxy Mode: WPAD")

$proxyConfig = $noProxyConfig

# set of initial command that will be sent to codec
$initialCommands = @(
"xConfiguration UserInterface Language: $language",
"xConfiguration Time Zone: $timeZone",
"xConfiguration Time TimeFormat: $timeFormat",
"xConfiguration Time DateFormat: $dateFormat") + $proxyConfig


# set to $false if registering for MTR mode
$closeInitialWizard = $true # $false

# new local user
$localUser = @{
    Active = "True";
    Username = "cisco";
    Passphrase = "C1sco123";
    PassphraseChangeRequired = "False";
    Role = @("Admin", "Audit", "User", "Integrator", "RoomControl");
    ShellLogin = "True"
}

#
# APPLICATION CONFIGURATION
#

# proxy server
$httpProxy = [System.Environment]::GetEnvironmentVariable('PROXY_URL')

# Define database connection parameters
$serverName = [System.Environment]::GetEnvironmentVariable('DATABASE_SERVER')
$databaseName = [System.Environment]::GetEnvironmentVariable('DATABASE_MAME')
$dbUsername = [System.Environment]::GetEnvironmentVariable('DATABASE_USER')
$dbPassword = [System.Environment]::GetEnvironmentVariable('DATABASE_PASSWORD')

# Webex Integration Client Id
$clientId = [System.Environment]::GetEnvironmentVariable('WEBEX_CLIENT_ID')

# URLs for Webex Access Token management
$tokenRenewUrl = [System.Environment]::GetEnvironmentVariable('TOKEN_REFRESH_URL')
$tokenPage = [System.Environment]::GetEnvironmentVariable('TOKEN_CREATE_URL')

# ignore certificate errors
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# accept any TLS version
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Import the SQL Server module
Import-Module SqlServer

# perform SQL request
function sql($sqlText, $database = "master", $server = ".", $username = "sa", $password)
{
    $connection = new-object System.Data.SqlClient.SQLConnection("Data Source=$server;User Id=$username;Password=$password;Initial Catalog=$database");
    $cmd = new-object System.Data.SqlClient.SqlCommand($sqlText, $connection);

    $connection.Open();
    $reader = $cmd.ExecuteReader()

    $results = @()
    while ($reader.Read())
    {
        $row = @{}
        for ($i = 0; $i -lt $reader.FieldCount; $i++)
        {
            $row[$reader.GetName($i)] = $reader.GetValue($i)
        }
        $results += new-object psobject -property $row            
    }
    $connection.Close();

    $results
}

# create header for HTTP requests to the Webex API
function createWebexHeaders($accessToken) {
    $headers = @{"Authorization" = "Bearer "+ $accessToken;
        "Accept" = "application/json"
    }

    $headers
}

# GET from Webex API
function webexGet($path, $params = $null, $accessToken) {
    $headers = createWebexHeaders -accessToken $accessToken

    if ($params) {
        # Convert the parameters to a query string
        $queryString = "?" + ($params.GetEnumerator() | ForEach-Object { "$([System.Web.HttpUtility]::UrlEncode($_.Key))=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    } else {
        $queryString = ""
    }
    $uriWithParams = "https://webexapis.com/v1" + $path + $queryString

    Write-Host "query URL: $uriWithParams"

    try {
        $resp = Invoke-RestMethod -Uri $uriWithParams -Method Get -Headers $headers -Proxy $httpProxy

        $resp
    } catch {
        Write-Host "webex API GET request error: $_.Exception.Response"
    }
}

# POST to Webex API
function webexPost($path, $params = $null, $body, $accessToken) {
    $headers = createWebexHeaders -accessToken $accessToken

    if ($params) {
        # Convert the parameters to a query string
        $queryString = "?" + ($params.GetEnumerator() | ForEach-Object { "$([System.Web.HttpUtility]::UrlEncode($_.Key))=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    } else {
        $queryString = ""
    }
    $uriWithParams = "https://webexapis.com/v1" + $path + $queryString

    Write-Host "query URL: $uriWithParams"

    try {
        $resp = Invoke-RestMethod -Uri $uriWithParams -Method Post -Headers $headers -Body ($body|ConvertTo-Json) -ContentType "application/json"  -Proxy $httpProxy

        $resp
    } catch {
        Write-Host "webex API POST request error: $_.Exception.Response"
    }
}

# PUT to Webex API
function webexPut($path, $params = $null, $body, $accessToken) {
    $headers = createWebexHeaders -accessToken $accessToken

    if ($params) {
        # Convert the parameters to a query string
        $queryString = "?" + ($params.GetEnumerator() | ForEach-Object { "$([System.Web.HttpUtility]::UrlEncode($_.Key))=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    } else {
        $queryString = ""
    }
    $uriWithParams = "https://webexapis.com/v1" + $path + $queryString

    Write-Host "query URL: $uriWithParams"

    try {
        $resp = Invoke-RestMethod -Uri $uriWithParams -Method Put -Headers $headers -Body ($body|ConvertTo-Json) -ContentType "application/json"  -Proxy $httpProxy

        $resp
    } catch {
        Write-Host "webex API PUT request error: $_.Exception.Response"
    }
}


# convert command line format to XML so it can be used by putXML function
function parseCommandToXML($inputString) {
#    Write-Host "input: $inputString"

    # Use regular expressions to split the string
    $matches = ([regex]::Matches($inputString, '(\w+:\s+[^\s]+)|(\w+[^:])') | %{$_.value})
#    Write-Host "matches: $matches"

    $first, $rest= $matches
#    Write-Host "rest: $rest"

    $xml = "<{0}/>" -f $first.TrimStart("x")
    $doc = [System.Xml.Linq.XDocument]::Parse($xml)
    $parent = $doc.Root
    # Iterate through the matches and separate them into prefix and pairs
    foreach ($match in $rest) {
        $cmdPart = $match.Trim()
        if ($cmdPart -match '(\w+:\s+[^\s]+)') {
            $cmdMatch = [regex]::Match($cmdPart, '(\w+):\s+([^\s]+)')
            $key = $cmdMatch.Groups[1].value
            $value = $cmdMatch.Groups[2].value
#            Write-Host "key: $key, value: $value - $(@($key, $value))"
            $parent.Add([System.Xml.Linq.XElement]::Parse("<{0}>{1}</{0}>" -f @($key, $value)))
        } else {
#            Write-Host "value: $value"
            $parent.Add([System.Xml.Linq.XElement]::Parse("<{0}/>" -f $cmdPart))
            $parent = $parent.Descendants($cmdPart)[0]
        }
    }

#    Write-Host "final XML: $($doc.toString())"

    $doc
}

# convert command line format to a "path" which can be used by getXML function
# only commands without parameters can be converted, others have to be sent to putXML
function parseCommandToPath($inputString) {
    $matches = ([regex]::Matches($inputString, '(\w+)') | %{$_.value})

    $first, $rest= $matches
    $result = "/$($first.TrimStart('x'))/$($rest -join '/')"

    $result
}

# create header for HTTP requests to the codec
function createCodecHeaders($username, $password) {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $userName,$password)))
    $headers = @{"Authorization" = "Basic "+ $base64AuthInfo;}

    $headers
}

# run a command via getxml URL on codec API (HTTP GET)
function getXML($deviceIP, $command, $username = "admin", $password = "") {
    $headers = createCodecHeaders -username $username -password $password

    $path = parseCommandToPath -inputString $command

    $url = "https://"+ $deviceIP +"/getxml?location=" + $path;
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Get -Headers $headers

        $resp
    } catch { 
        Write-Host "http request error: $_.Exception.Response"
    }

}

# run a command via putxml URL on codec API (HTTP POST)
function putXML($deviceIP, $command, $username = "admin", $password = "") {
    $headers = createCodecHeaders -username $username -password $password

    $url = "https://"+ $deviceIP +"/putxml?location=" + $path;
    try {
        $xml = parseCommandToXML -inputString $command
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -ContentType "text/xml" -Body $xml.ToString()

        $resp
    } catch { 
        Write-Host "http request error: $_.Exception.Response"
    }

}


#
# main()
#

# get Webex Access Token from the database
$query = "SELECT accessToken,expires FROM WebexTokens WHERE clientId='$clientId'"
$result = sql $query -server $serverName -password $dbPassword

if (!$result.accessToken) {
  Write-Host "database provided no access token, open $tokenPage and create one there"
  exit 1
}

# Work with query results (e.g., display or process data)
# $result.accessToken | Format-Table -AutoSize

$accessToken = $result.accessToken
$expires = Get-Date $result.expires
$now = Get-Date

#Write-Host "access token: $accessToken"
if ($expires -gt $now) {
  Write-Host "token valid until $expires"
} else {
# refresh Access Token if expired
  Write-Host "token expired, requesting a refresh"
  $refreshResult = Invoke-WebRequest -Uri $tokenRenewUrl
  $statusCode = $refreshResult.StatusCode
  $statusDescription = $refreshResult.StatusDescription
  Write-Host "refresh result: $statusCode $statusDescription"
  if ($statusCode -eq 200) {
    $result = sql $query -server $serverName -password $dbPassword
    $accessToken = $result.accessToken
    $expires = Get-Date $result.expires
    Write-Host "access token now expires $expires"
  } else {
    Write-Host "token refresh failed"
    exit 1
  }
}

# We now have a valid access token in $accessToken variable

$res = getXML -deviceIP $deviceIP -command "xStatus SystemUnit" -username $username -password $password
$serialNumber = $res.Status.SystemUnit.Hardware.Module.SerialNumber
Write-Host "connected to: $($res.Status.SystemUnit.ProductId), SN: $serialNumber, SW: $($res.Status.SystemUnit.Software.DisplayName)"


#
# DEVICE INITIALIZATION PROCEDURE
#

#
# STEP 1: initialize the device - set date, time & language and http proxy
#
foreach ($command in $initialCommands) {
    Write-Host "running command: $command"

    $res = putXML -deviceIP $deviceIP -command $command  -username $username -password $password
    
    Write-Host "command result: $($res.InnerXml)"
}

#
# STEP 2: search for existing workspace, create a new one if not found
#   also search & create a location of the workspace
#

$locationAddressData = @{
    address1 = $location.address1;
    address2 = $location.address2;
    postalCode = $location.zip;
    city = $location.cityName;
    state = $location.state;
    country = $location.countryCode
}
$locationData = @{
    name = $location.displayName;
    timeZone = $location.timeZone;
    address = $locationAddressData;
    latitude = $location.latitude;
    longitude = $location.longitude  
}
if ($location.address2.Length > 0) {
    $wsLocAddress = $location.address1+", "+$location.address2
} else {
    $wsLocAddress = $location.address1
}
$wsLocationData = @{
    displayName = $location.displayName;
    address = $wsLocAddress;
    countryCode = $location.countryCode;
    cityName = $location.cityName;
    latitude = $location.latitude;
    longitude = $location.longitude  
}

$wsLoc = webexGet -path "/workspaceLocations" -params @{displayName = $location.displayName} -accessToken $accessToken
if ($wsLoc.items.Count -eq 0) {
    Write-Host "location '$($location.displayName)' not found, creating new one"
    $wsLoc = webexPost -path "/workspaceLocations" -body $wsLocationData -accessToken $accessToken

    $wsLocationId = $wsLoc.id
    $locationId = $wsLoc.locationId
    Write-Host "workspace location created: $wsLocationId, location id: $locationId"
    webexPut -path "/locations/$locationId" -body $locationData -accessToken $accessToken
} else {
    Write-Host "workspace location '$($location.displayName)' found: $($wsLoc.items[0].id)"
    $wsLocationId = $wsLoc.items[0].id
}

$res = webexGet -path "/workspaces" -params @{displayName = $workspaceName} -accessToken $accessToken
if ($res.items.Count -eq 0) {
    Write-Host "workspace '$workspaceName' not found, creating new one"
    $res = webexPost -path "/workspaces" -body @{displayName = $workspaceName; "workspaceLocationId" = $wsLocationId} -accessToken $accessToken

    Write-Host "workspace created: $($res.id)"
    $workspaceId = $res.id
} else {
    Write-Host "workspace found: $($res.items[0].id)"
    $workspaceId = $res.items[0].id
}


#
# STEP 3: optionally stop the initial wizard
#
if ($closeInitialWizard) {
    $stopCommand = "xCommand SystemUnit FirstTimeWizard Stop"
    $res = putXML -deviceIP $deviceIP -command $stopCommand -username $username -password $password
    Write-Host "first time wizard stop result: $($res.InnerXml)"
}

#
# STEP 4: create activation code for the workspaceId
#
$res = webexPost -path "/devices/activationCode" -body @{"workspaceId" = $workspaceId} -accessToken $accessToken
$activationCode = $res.code
Write-Host "activation code generated: $(($activationCode -split '(.{4})' | ? {$_}) -join '-'), expires: $($res.expiryTime)"

#
# STEP 5: register device using activation code
#
Start-Sleep -Seconds 5
Write-Host "initiate device registration"
$actCommand = "xCommand Webex Registration Start RegistrationType: Manual SecurityAction: Harden ActivationCode: $activationCode"
$res = putXML -deviceIP $deviceIP -command $actCommand -username $username -password $password
Write-Host "device registration result: $($res.InnerXml)"

#
# STEP 6: wait for the device to register - check status on Webex, get deviceId
#
$deviceRegistered = $false

# find the device registration in the Webex Workspace
while (!$deviceRegistered) {
    $res = webexGet -path "/devices" -params @{workspaceId = $workspaceId} -accessToken $accessToken

    if ($res.items.Count -gt 0) {
        foreach ($device in $res.items) {
            if ($device.serial -eq $serialNumber) {
                # device found, check connection status
                $deviceRegistered = ($device.connectionStatus -in @("connected", "connected_with_issues"))
                Write-Host "device found in Webex, connection status: $($device.connectionStatus)"

                break
            }
        }
    } else {
        Write-Host "no device found"
        $deviceRegistered = $false
    }

    if (!$deviceRegistered) {
        Write-Host "delay before another device registration check"
        Start-Sleep -Seconds 5
    }
}

#
# STEP 7: once the device is registered, create a local user (using Webex xAPI)
#
Start-Sleep -Seconds 5
Write-Host "post-registration action start"
$xCommand = "UserManagement.User.Add"
$body = @{
  deviceId = $device.id;
  arguments = $localUser;
}
$res = webexPost -path "/xapi/command/$xCommand" -body $body -accessToken $accessToken

$xCommand = "xConfiguration UserInterface Language: $language"

#
# STEP 8: check the device access using the local user
#

Start-Sleep -Seconds 5
Write-Host "post-registration action complete, checking access to the device using local user"
$res = getXML -deviceIP $deviceIP -command "xStatus SystemUnit" -username $localUser.Username -password $localUser.Passphrase
$serialNumber = $res.Status.SystemUnit.Hardware.Module.SerialNumber
Write-Host "connected to: $($res.Status.SystemUnit.ProductId), SN: $serialNumber, SW: $($res.Status.SystemUnit.Software.DisplayName)"
