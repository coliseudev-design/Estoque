namespace ColiseuSpeed.Worker.Config;

public class VisionApiOptions
{
    public const string Section = "VisionApi";

    public string BaseUrl { get; set; } = string.Empty;
    public string InternalApiKey { get; set; } = string.Empty;
    public int TimeoutSeconds { get; set; } = 30;
    public bool Enabled { get; set; } = false;
}
