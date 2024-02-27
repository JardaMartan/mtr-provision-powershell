# device configuration parameters
$deviceIP = "10.229.102.66"
$minSWversion = "11.13.1"
$waitTime = 90 # seconds for reboot

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
$initialCommands = $proxyConfig


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

function verifySWversion($minVersion, $deviceIP, $username = "admin", $password = "") {
    $result = $true

    $res = getXML -deviceIP $deviceIP -username $username -password $password -command "xStatus SystemUnit Software DisplayName"
    Write-Host "version info: $($res.Status.SystemUnit.Software.DisplayName)"

    $versionMatch = [regex]::Match($res.Status.SystemUnit.Software.DisplayName, '^RoomOS ([\d\.]+) ')
    $version = $versionMatch.Groups[1].Value
    $verArr = $version.Split(".")

    $minArr = $minVersion.Split(".")

    if ($verArr.Count -lt $minArr.Count) {
        Write-Host "invalid version parsed from the device: $version"
    } else {
        for (($i = 0); ($i -lt $minArr.Count); $i++) {
            if ([int]$verArr[$i] -gt [int]$minArr[$i]) {
                break
            } else {
                if ([int]$verArr[$i] -lt [int]$minArr[$i]) {
                    $result = $false
                    break
                }
            }
        }
    }

    $result
}


#
# main()
#

#
# DEVICE INITIALIZATION PROCEDURE
#

#
# STEP 1: initialize the device - set http proxy
#
foreach ($command in $initialCommands) {
    Write-Host "running command: $command"

    $res = putXML -deviceIP $deviceIP -command $command  -username $username -password $password
    
    Write-Host "command result: $($res.InnerXml)"
}

#
# STEP 2: get current software version and check if it's greater or equal to the lowest acceptable
#
if (verifySWversion -minVersion $minSWversion -deviceIP $deviceIP -username $username -password $password) {
    Write-Host "minimal SW version OK"
} else {
    Write-Host "performing SW upgrade"

#
# STEP 3: if upgrade needed, get the device ProductPlatform name
#
    $res = getXML -deviceIP $deviceIP -username $username -password $password -command "xStatus SystemUnit ProductPlatform"
    $platform = $res.Status.SystemUnit.ProductPlatform
    Write-Host "detected platform: '$platform'"

#
# STEP 4: get the software manifest and read the packageLocation URL
#
    $manifestURL = "https://client-upgrade-a.wbx2.com/client-upgrade/api/v1/ce/upgrade/@me?channel=Stable&model=" + [System.Web.HttpUtility]::UrlEncode($platform)
    Write-Host "get manifest from: $manifestURL"
    $res = Invoke-RestMethod -Method Get -Uri $manifestURL -Proxy $httpProxy
    $newVersion = $res.manifest.version
    $model = $res.manifest.model
    $locationURL = $res.manifest.packageLocation
    Write-Host "new software version: '$newVersion' for '$model' at $locationURL"

#
# STEP 5: perform software upgrade (wait for completion)
#
    Write-Host "starting SW download to device"
    $res = putXML -deviceIP $deviceIP -username $username -password $password -command "xCommand  SystemUnit SoftwareUpgrade URL: $locationURL"
    Write-Host "download complete"

    Start-Sleep -Seconds 5
    $res = getXML -deviceIP $deviceIP -username $username -password $password -command "xStatus Provisioning Software UpgradeStatus Status"
    $status = $res.Status.Provisioning.Software.UpgradeStatus.Status
    Write-Host "upgrade status: $status"

#
# STEP 6: verify SW version
#
    Write-Host "waiting $waitTime s to reboot"
    Start-Sleep -Seconds $waitTime

    if (verifySWversion -minVersion $minSWversion -deviceIP $deviceIP -username $username -password $password) {
        Write-Host "minimal SW version OK"
    } else {
        Write-Host "check version and upgrade manually"
    }

}