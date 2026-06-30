namespace ColiseuSpeed.Worker.Config;

public class DashboardApiOptions
{
    public const string Section = "DashboardApi";

    public string BaseUrl { get; set; } = string.Empty;
    public string InternalApiKey { get; set; } = string.Empty;
    public int TimeoutSeconds { get; set; } = 30;
    public bool Enabled { get; set; } = false;
}
