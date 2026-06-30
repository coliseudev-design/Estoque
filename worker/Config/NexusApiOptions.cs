namespace ColiseuSpeed.Worker.Config;

public class NexusApiOptions
{
    public const string Section = "NexusApi";

    public string BaseUrl { get; set; } = string.Empty;
    public string InternalApiKey { get; set; } = string.Empty;
    public int TimeoutSeconds { get; set; } = 30;
    public bool Enabled { get; set; } = false;
}
