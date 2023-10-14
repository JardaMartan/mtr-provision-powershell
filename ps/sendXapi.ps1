$deviceIP = "10.229.102.55"
$username = "admin"
$password = ""

$timeZone = "Europe/Prague"
$timeFormat = "24H"
$dateFormat = "DD_MM_YY"
$closeInitialWizard = $false # $true
$language = "Czech"

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
"xConfiguration Time Zone: $timeZone",
"xConfiguration Time TimeFormat: $timeFormat",
"xConfiguration Time DateFormat: $dateFormat",
"xConfiguration UserInterface Language: $language") + $proxyConfig


# ignore server certificate
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
function createHeaders($username, $password) {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $userName,$password)))
    $headers = @{"Authorization" = "Basic "+ $base64AuthInfo;}

    $headers
}

# run a command via getxml URL on codec API (HTTP GET)
function getXML($deviceIP, $command, $username = "admin", $password = "") {
    $headers = createHeaders -username $username -password $password

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
    $headers = createHeaders -username $username -password $password

    $url = "https://"+ $deviceIP +"/putxml?location=" + $path;
    try {
        $xml = parseCommandToXML -inputString $command
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -ContentType "text/xml" -Body $xml.ToString()

        $resp
    } catch { 
        Write-Host "http request error: $_.Exception.Response"
    }

}


$res = getXML -deviceIP $deviceIP -command "xStatus SystemUnit" -username $username -password $password
Write-Host "connected to: $($res.Status.SystemUnit.ProductId), SN: $($res.Status.SystemUnit.Hardware.Module.SerialNumber), SW: $($res.Status.SystemUnit.Software.DisplayName)"

#$res = putXML -deviceIP $deviceIP -command "xConfiguration WebEngine Mode: On" -username $username -password $password
#Write-Host "webengine set result: $($res.InnerXml)"

#$res = putXML -deviceIP $deviceIP -command "xCommand UserManagement User Get Username: cisco" -username $username -password $password
#Write-Host "current webengine config: $($res.InnerXml)"


#
# STEP 1: initialize codec - set date, time & language and http proxy
#
foreach ($command in $initialCommands) {
    Write-Host "running command: $command"

    $res = putXML -deviceIP $deviceIP -command $command  -username $username -password $password
    
    Write-Host "command result: $($res.InnerXml)"
}