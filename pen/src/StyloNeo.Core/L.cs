namespace StyloNeo.Core;

/// <summary>
/// Console language (English by default, French on request). Every user-visible string goes through
/// <see cref="T"/>; identifiers, JSON keys, file names and exit codes never change.
/// </summary>
public static class L
{
    /// <summary>Environment variable read when <c>--lang</c> is not given.</summary>
    public const string EnvVar = "STYLO_NEO_LANG";

    /// <summary>true: French messages; false (default): English.</summary>
    public static bool Fr { get; set; }

    /// <summary>Returns the message in the current language.</summary>
    public static string T(string en, string fr) => Fr ? fr : en;

    /// <summary>
    /// Chooses the language: the <c>--lang</c> option first, else the environment variable, else English.
    /// Returns true for French. Throws <see cref="ArgumentException"/> on any value other than en / fr.
    /// </summary>
    public static bool Resolve(string? option, string? environment)
    {
        var value = option ?? (string.IsNullOrWhiteSpace(environment) ? null : environment);
        if (value is null) return false;
        return value.Trim().ToLowerInvariant() switch
        {
            "en" => false,
            "fr" => true,
            _ => throw new ArgumentException(option is not null
                ? $"--lang expects en or fr (got: {value})."
                : $"{EnvVar} expects en or fr (got: {value})."),
        };
    }

    /// <summary>A yes answer to a (y/N) question: y / yes, and in French also o / oui.</summary>
    public static bool IsYes(string? answer)
    {
        var a = answer?.Trim().ToLowerInvariant();
        return a is "y" or "yes" || (Fr && a is "o" or "oui");
    }
}
