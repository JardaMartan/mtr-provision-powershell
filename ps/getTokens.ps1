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

Write-Host "access token: $accessToken"
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