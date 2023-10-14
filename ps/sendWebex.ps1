# Import the SQL Server module
Import-Module SqlServer

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

# create header for HTTP requests to the Webex API
function createHeaders($accessToken) {
    $headers = @{"Authorization" = "Bearer "+ $accessToken;
        "Accept" = "application/json"
    }

    $headers
}

function webexGet($path, $params = $null, $accessToken) {
    $headers = createHeaders -accessToken $accessToken

    if ($params) {
        # Convert the parameters to a query string
        $queryString = "?" + ($params.GetEnumerator() | ForEach-Object { "$([System.Web.HttpUtility]::UrlEncode($_.Key))=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    } else {
        $queryString = ""
    }
    $uriWithParams = "https://webexapis.com/v1" + $path + $queryString

    Write-Host "query URL: $uriWithParams"

    try {
        $resp = Invoke-RestMethod -Uri $uriWithParams -Method Get -Headers $headers

        $resp
    } catch {
        Write-Host "webex API request error: $_.Exception.Response"
    }
}

function webexPost($path, $params = $null, $body, $accessToken) {
    $headers = createHeaders -accessToken $accessToken

    if ($params) {
        # Convert the parameters to a query string
        $queryString = "?" + ($params.GetEnumerator() | ForEach-Object { "$([System.Web.HttpUtility]::UrlEncode($_.Key))=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    } else {
        $queryString = ""
    }
    $uriWithParams = "https://webexapis.com/v1" + $path + $queryString

    Write-Host "query URL: $uriWithParams"

    try {
        $resp = Invoke-RestMethod -Uri $uriWithParams -Method Post -Headers $headers -Body ($body|ConvertTo-Json) -ContentType "application/json"

        $resp
    } catch {
        Write-Host "webex API request error: $_.Exception.Response"
    }
}


#$res = webexGet -path "/people/Y2lzY29zcGFyazovL3VzL1BFT1BMRS80MzY5Y2UzYi1iMmIyLTQ5YzUtYTEwZC1jYzFlYTczMGU5N2Q" -accessToken $accessToken
#Write-Host "result: $($res.displayName)"

$workspaceName = "Test"

#
# STEP 2: search for existing space, create a new one if not found
#
$res = webexGet -path "/workspaces" -params @{"displayName" = $workspaceName} -accessToken $accessToken
if ($res.items.Count -eq 0) {
    Write-Host "workspace '$workspaceName' not found, creating new one"
    $res = webexPost -path "/workspaces" -body @{"displayName" = $workspaceName} -accessToken $accessToken

    Write-Host "workspace created: $($res.id)"
    $workspaceId = $res.id
} else {
    Write-Host "workspace found: $($res.items[0].id)"
    $workspaceId = $res.items[0].id
}


#
# STEP 3: create activation code for the workspaceId
#
$res = webexPost -path "/devices/activationCode" -body @{"workspaceId" = $workspaceId} -accessToken $accessToken
$activationCode = $res.code
Write-Host "activation code generated: $(($activationCode -split '(.{4})' | ? {$_}) -join '-'), expires: $($res.expiryTime)"

#
# STEP 4: register device using activation code
#

#
# STEP 5: optionally stop the initial wizard
#

#
# STEP 6: once the device is registered, create a local user (using Webex xAPI)
#