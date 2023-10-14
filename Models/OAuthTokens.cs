namespace OAuth.Models
{
    public class OAuthTokens
    {
        public string access_token { get; set; }
        public int expires_in { get; set; }
        public string expires { get; set; }
        public string refresh_token { get; set; }
        public int refresh_token_expires_in { get; set; }
        public string refresh_token_expires { get; set; }
        public string token_type { get; set; }
    }
}
