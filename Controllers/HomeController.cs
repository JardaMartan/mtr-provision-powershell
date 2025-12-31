using Microsoft.AspNetCore.Mvc;
using OAuth.Models;
using System.Diagnostics;
using System.Text.Encodings.Web;
using System;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Text.Json;
//using System.Data.SqlClient;
using Microsoft.Data.SqlClient;

namespace OAuth.Controllers
{
    public class HomeController : Controller
    {
        static string databaseServer = Environment.GetEnvironmentVariable("DATABASE_SERVER");
        static string databaseName = Environment.GetEnvironmentVariable("DATABASE_NAME");
        static string databaseUser = Environment.GetEnvironmentVariable("DATABASE_USER");
        static string databasePassword = Environment.GetEnvironmentVariable("DATABASE_PASSWORD");
        static string useIntegratedSecurity = Environment.GetEnvironmentVariable("USE_INTEGRATED_SECURITY");

        // If USE_INTEGRATED_SECURITY is set to "true", use integrated security; otherwise, use SQL authentication
        static bool useIntegratedSecurityBool = useIntegratedSecurity?.ToLower() == "true";
        public static string connectionString;

        //static string connectionString = $"Server={databaseServer};Database={databaseName};User={databaseUser};Password={databasePassword};";

        static string UTCformat = "yyyy-MM-ddTHH:mm:ss.fffZ";
        static string ProxyUrl = Environment.GetEnvironmentVariable("PROXY_URL");

        static string WebexApiUrl = "https://webexapis.com/v1";
        static string authUrl = WebexApiUrl+ "/authorize";
        static string clientId = Environment.GetEnvironmentVariable("WEBEX_CLIENT_ID");
        static string clientSecret = Environment.GetEnvironmentVariable("WEBEX_CLIENT_SECRET");
        static string redirectUri = Environment.GetEnvironmentVariable("WEBEX_REDIRECT_URI");
        static String[] scopeList =
        {
                "spark-admin:workspaces_write",
                "spark-admin:locations_write",
                "spark:kms",
                "spark-admin:devices_read",
                "spark-admin:locations_read",
                "spark-admin:people_write",
                "spark-admin:workspace_locations_write",
                "spark-admin:workspace_locations_read",
                "spark-admin:workspaces_read",
                "spark-admin:devices_write",
                "spark-admin:people_read",
                "identity:placeonetimepassword_create",
                "spark:xapi_statuses",
                "spark:xapi_commands"
            };

        private readonly ILogger<HomeController> _logger;

        public HomeController(ILogger<HomeController> logger)
        {
            _logger = logger;

            if (useIntegratedSecurityBool)
            {
                connectionString = $"Server={databaseServer};Database={databaseName};Integrated Security=True;";
            }
            else
            {
                connectionString = $"Server={databaseServer};Database={databaseName};User Id={databaseUser};Password={databasePassword};";
            }

            // Optional: Add encryption and trust server certificate settings for production environments
            connectionString += "Encrypt=True;TrustServerCertificate=True;"; // Adjust as per your SQL Server setup
        }

        public IActionResult Index()
        {
            ViewBag.Tokens = GetTokens(clientId);
            return View();
        }

        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }

        [HttpGet("hello")]
        public IActionResult Hello(string name)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                return BadRequest("Please provide a name parameter.");
            }

            return Content($"Hello, {name}!\nClient Id: {clientId}");
        }

        [HttpGet("callback")]
        public async Task<IActionResult> Callback(string code)
        {
            if (string.IsNullOrWhiteSpace(code))
            {
                return BadRequest("Code parameter missing.");
            }

            // Define the URL for the POST request
            string url = WebexApiUrl + "/access_token";

            var handler = new HttpClientHandler
            {
                Proxy = new WebProxy(ProxyUrl),
                UseProxy = true,
            };

            // Create an instance of HttpClient
            using (HttpClient httpClient = new HttpClient(handler))
            {
                try
                {
                    // Define the data to be sent in the POST request
                    string data = "grant_type=authorization_code" +
                        "&redirect_uri=" + System.Net.WebUtility.UrlEncode(redirectUri) +
                        "&client_id=" + clientId +
                        "&client_secret=" + clientSecret +
                        "&code=" + code;

                    // Create a StringContent object to hold the data
                    var content = new StringContent(data, System.Text.Encoding.ASCII, "application/x-www-form-urlencoded");

                    // Send the POST request
                    HttpResponseMessage response = await httpClient.PostAsync(url, content);

                    // Check if the request was successful (status code 200 OK)
                    if (response.IsSuccessStatusCode)
                    {
                        // Read the response content as a string
                        string responseBody = await response.Content.ReadAsStringAsync();

                        try
                        {
                            OAuthTokens oAuthTokens = JsonSerializer.Deserialize<OAuthTokens>(responseBody);

                            DateTime exp = DateTime.UtcNow.AddSeconds(oAuthTokens.expires_in);
                            oAuthTokens.expires = exp.ToString(UTCformat);

                            DateTime refresh_exp = DateTime.UtcNow.AddSeconds(oAuthTokens.refresh_token_expires_in);
                            oAuthTokens.refresh_token_expires = refresh_exp.ToString(UTCformat);

                            Boolean saveResult = SaveTokens(oAuthTokens);

 /*                           return Content($"Access and refresh tokens: {oAuthTokens.access_token} -> {oAuthTokens.expires}\n" +
                                $"{oAuthTokens.refresh_token} -> {oAuthTokens.refresh_token_expires}\n" +
                                $"Save result: {saveResult}");*/

                            return RedirectToAction("Index", "Home");
                        } catch (Exception ex)
                        {
                            return Content($"JSON parsing error: {ex.Message}");
                        }
                    }
                    else
                    {
                        return Content($"Request failed with status code: {response.StatusCode}");
                    }
                }
                catch (Exception ex)
                {
                    return Content($"An error occurred: {ex.Message}");
                }
            }
        }

        [HttpGet("refresh")]
        public async Task<IActionResult> Refresh()
        {
            OAuthTokens storedTokens = GetTokens(clientId);

            if (storedTokens == null)
            {
                return Content("No tokens found in database.");
            }

            string url = WebexApiUrl + "/access_token";

            var handler = new HttpClientHandler
            {
                Proxy = new WebProxy(ProxyUrl),
                UseProxy = true,
            };

            // Create an instance of HttpClient
            using (HttpClient httpClient = new HttpClient(handler))
            {
                try
                {
                    // Define the data to be sent in the POST request
                    string data = "grant_type=refresh_token" +
                        "&redirect_uri=" + System.Net.WebUtility.UrlEncode(redirectUri) +
                        "&client_id=" + clientId +
                        "&client_secret=" + clientSecret +
                        "&refresh_token=" + storedTokens.refresh_token;

                    // Create a StringContent object to hold the data
                    var content = new StringContent(data, System.Text.Encoding.ASCII, "application/x-www-form-urlencoded");

                    // Send the POST request
                    HttpResponseMessage response = await httpClient.PostAsync(url, content);

                    // Check if the request was successful (status code 200 OK)
                    if (response.IsSuccessStatusCode)
                    {
                        // Read the response content as a string
                        string responseBody = await response.Content.ReadAsStringAsync();

                        try
                        {
                            OAuthTokens oAuthTokens = JsonSerializer.Deserialize<OAuthTokens>(responseBody);

                            DateTime exp = DateTime.UtcNow.AddSeconds(oAuthTokens.expires_in);
                            oAuthTokens.expires = exp.ToString(UTCformat);

                            DateTime refresh_exp = DateTime.UtcNow.AddSeconds(oAuthTokens.refresh_token_expires_in);
                            oAuthTokens.refresh_token_expires = refresh_exp.ToString(UTCformat);

                            Boolean saveResult = SaveTokens(oAuthTokens);

/*                            return Content($"Access and refresh tokens: {oAuthTokens.access_token} -> {oAuthTokens.expires}\n" +
                                $"{oAuthTokens.refresh_token} -> {oAuthTokens.refresh_token_expires}\n" +
                                $"Save result: {saveResult}");*/

                            return RedirectToAction("Index", "Home");
                        }
                        catch (Exception ex)
                        {
                            return Content($"JSON parsing error: {ex.Message}");
                        }
                    }
                    else
                    {
                        return Content($"Request failed with status code: {response.StatusCode}");
                    }
                }
                catch (Exception ex)
                {
                    return Content($"An error occurred: {ex.Message}");
                }
            }
        }

        public OAuthTokens GetTokens(string clientId)
        {
            using (SqlConnection connection = new SqlConnection(connectionString))
            {
                connection.Open();

                string sqlQuery = $"SELECT * FROM WebexTokens WHERE clientId='{clientId}'";
                // Create a SqlCommand object with the SQL query and the SqlConnection
                using (SqlCommand command = new SqlCommand(sqlQuery, connection))
                {
                    // Execute the query and obtain a SqlDataReader
                    using (SqlDataReader reader = command.ExecuteReader())
                    {
                        if (reader.Read())
                        {
                            OAuthTokens oAuthTokens = new OAuthTokens();
                            oAuthTokens.access_token = reader.GetString(2);
                            oAuthTokens.expires = reader.GetString(3);
                            oAuthTokens.refresh_token = reader.GetString(4);
                            oAuthTokens.refresh_token_expires = reader.GetString(5);

                            connection.Close();

                            return oAuthTokens;
                        } else
                        {
                            connection.Close();

                            return null;
                        }
                    }
                }
            }
        }

        public Boolean SaveTokens(OAuthTokens oAuthTokens)
        {

            OAuthTokens savedTokens = GetTokens(clientId);
            Boolean result = false;

            using (SqlConnection connection = new SqlConnection(connectionString))
            {
                connection.Open();
                string sqlQuery = "";
                if (savedTokens != null)
                {
                    sqlQuery = $"UPDATE WebexTokens " +
                        $"SET accessToken='{oAuthTokens.access_token}', expires='{oAuthTokens.expires}', " +
                        $"refreshToken='{oAuthTokens.refresh_token}', refreshExpires='{oAuthTokens.refresh_token_expires}' " +
                        $"WHERE clientId='{clientId}'";
                }
                else
                {
                    sqlQuery = $"INSERT INTO WebexTokens (clientId, accessToken, expires, refreshToken, refreshExpires)" +
                        $"VALUES ('{clientId}', '{oAuthTokens.access_token}', '{oAuthTokens.expires}', " +
                        $"'{oAuthTokens.refresh_token}', '{oAuthTokens.refresh_token_expires}')";

                }
                using (SqlCommand command = new SqlCommand(sqlQuery, connection))
                {
                    int affectedLines = command.ExecuteNonQuery();
                    result = (affectedLines > 0);
                }

                connection.Close();
            }

            return result;
        }

        [HttpGet("authorize")]
        public IActionResult Authorize()
        {
            string scope = string.Join(" ", scopeList);
            string resultUrl = authUrl + "?client_id=" + clientId + "&redirect_uri=" + System.Net.WebUtility.UrlEncode(redirectUri) + "&scope=" + System.Net.WebUtility.UrlEncode(scope) + "&response_type=code";

            return Redirect(resultUrl);
        }
    }
}