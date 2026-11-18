using StyloNeo.Core;

namespace StyloNeo.Tests;

/// <summary>Language selection (--lang, then STYLO_NEO_LANG, then English) and French messages.</summary>
public class LocalisationTests
{
    [Fact]
    public void Default_is_English() => Assert.False(L.Resolve(null, null));

    [Fact]
    public void Empty_environment_variable_is_ignored() => Assert.False(L.Resolve(null, "  "));

    [Theory]
    [InlineData("fr", true)]
    [InlineData("FR", true)]
    [InlineData("en", false)]
    public void Environment_variable_selects_the_language(string env, bool fr) => Assert.Equal(fr, L.Resolve(null, env));

    [Fact]
    public void Option_wins_over_environment_variable()
    {
        Assert.True(L.Resolve("fr", "en"));
        Assert.False(L.Resolve("en", "fr"));
    }

    [Theory]
    [InlineData("de", null)]
    [InlineData(null, "francais")]
    [InlineData("", "fr")]
    public void Invalid_value_is_rejected(string? option, string? env) =>
        Assert.Throws<ArgumentException>(() => L.Resolve(option, env));

    [Fact]
    public void Translation_and_yes_answers_follow_the_language()
    {
        bool before = L.Fr;
        try
        {
            L.Fr = false;
            Assert.Equal("strokes", L.T("strokes", "traits"));
            Assert.True(L.IsYes("Y"));
            Assert.False(L.IsYes("o"));
            Assert.Equal("nothing received", new NotebookReport("3-27-738", NotebookState.NothingReceived, 0, 0).Label);

            L.Fr = true;
            Assert.Equal("traits", L.T("strokes", "traits"));
            Assert.True(L.IsYes(" Oui "));
            Assert.True(L.IsYes("o"));
            Assert.True(L.IsYes("yes"));
            Assert.False(L.IsYes(""));
            Assert.False(L.IsYes(null));
            Assert.Equal("INCOMPLET (3/10 traits conservés)",
                         new NotebookReport("3-27-738", NotebookState.Incomplete, 3, 10).Label);
        }
        finally { L.Fr = before; }
    }
}
