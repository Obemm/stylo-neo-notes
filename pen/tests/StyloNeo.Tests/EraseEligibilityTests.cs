using StyloNeo.Core;

namespace StyloNeo.Tests;

/// <summary>Which notebooks may leave the pen: --erase (end confirmed) and --erase-received (all announced strokes).</summary>
public class EraseEligibilityTests
{
    [Theory]
    [InlineData(NotebookState.Complete, 10, 10, true, true)]
    [InlineData(NotebookState.EndNotConfirmed, 544, 544, false, true)]   // the large notebook that never sends its end
    [InlineData(NotebookState.EndNotConfirmed, 0, 0, false, false)]      // nothing announced: never erased
    [InlineData(NotebookState.Incomplete, 300, 544, false, false)]
    [InlineData(NotebookState.NothingReceived, 0, 544, false, false)]
    [InlineData(NotebookState.NotAttempted, 0, 0, false, false)]
    public void Eligibility(NotebookState state, int received, int total, bool eraseAllowed, bool allReceived)
    {
        var r = new NotebookReport("3-27-551", state, received, total);
        Assert.Equal(eraseAllowed, r.EraseAllowed);
        Assert.Equal(allReceived, r.AllReceived);
    }
}
