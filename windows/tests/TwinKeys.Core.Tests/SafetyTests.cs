namespace TwinKeys.Core.Tests;

public class SafetyTests
{
    [Fact]
    public void AllNotesOffDestinations()
    {
        foreach (var t in new[] { SafetyTrigger.PanicButton, SafetyTrigger.AppWillQuit, SafetyTrigger.ManualDisconnect })
        {
            Assert.Equal(new SafetyPlan(SafetyLocal.All, true), Safety.Plan(t, true));
            Assert.Equal(new SafetyPlan(SafetyLocal.All, false), Safety.Plan(t, false));
        }
        foreach (var t in new[] { SafetyTrigger.SendingTurnedOff, SafetyTrigger.KeyCaptureTurnedOff })
            Assert.Equal(new SafetyPlan(SafetyLocal.NotesFromKeys, true), Safety.Plan(t, true));
        foreach (var t in new[] { SafetyTrigger.ConnectionLost, SafetyTrigger.PeerSaidBye })
            Assert.Equal(new SafetyPlan(SafetyLocal.NotesFromPeer, false), Safety.Plan(t, true));
        foreach (var t in Enum.GetValues<SafetyTrigger>()) Assert.NotEqual(SafetyLocal.None, Safety.Plan(t, true).Local);
    }

    [Fact]
    public void AutoNoteOffAfterTimeout()
    {
        var g = new NoteGuard(10);
        g.Record(MidiMessage.NoteOn(0, 60, 100), 0);
        g.Record(MidiMessage.NoteOn(0, 64, 100), 5);
        Assert.Empty(g.Expire(9.9));
        Assert.Equal([MidiMessage.NoteOff(0, 60)], g.Expire(10));
        Assert.Equal([MidiMessage.NoteOff(0, 64)], g.Expire(15));
        Assert.Empty(g.Expire(100));
    }

    [Fact]
    public void NoteOffAndVelocityZeroCancelAutoOff()
    {
        var g = new NoteGuard(10);
        g.Record(MidiMessage.NoteOn(0, 60, 100), 0);
        g.Record(MidiMessage.NoteOff(0, 60), 1);
        g.Record(MidiMessage.NoteOn(2, 61, 100), 0);
        g.Record(MidiMessage.NoteOn(2, 61, 0), 1);
        Assert.Empty(g.Expire(20));
    }

    [Fact]
    public void KeepAndTouch()
    {
        var g = new NoteGuard(10);
        g.Record(MidiMessage.NoteOn(0, 60, 100), 0);
        g.Record(MidiMessage.NoteOn(0, 62, 100), 0);
        Assert.Equal([MidiMessage.NoteOff(0, 62)], g.Expire(11, new HashSet<NoteGuard.Key> { new(0, 60) }));
        g.Touch(0, 60, 11);
        Assert.Empty(g.Expire(20));
        Assert.Equal([MidiMessage.NoteOff(0, 60)], g.Expire(21));
    }

    [Fact]
    public void ZeroTimeoutDisablesAutoOff()
    {
        var g = new NoteGuard(0);
        g.Record(MidiMessage.NoteOn(0, 60, 100), 0);
        Assert.Empty(g.Expire(1000));
        Assert.Equal([MidiMessage.NoteOff(0, 60)], g.ReleaseAll());
    }

    [Fact]
    public void MidiBytesAndNoteNames()
    {
        Assert.Equal(new byte[] { 0x90, 36, 127 }, MidiMessage.NoteOn(0, 36, 127).Bytes);
        Assert.Equal(new byte[] { 0x8F, 37, 0 }, MidiMessage.NoteOff(15, 37).Bytes);
        Assert.Equal(16, MidiMessage.AllNotesOffBytes.Count);
        Assert.Equal(new byte[] { 0xB5, 123, 0 }, MidiMessage.AllNotesOffBytes[5]);
        Assert.Equal("C1", MidiMessage.NoteName(36));
        Assert.Equal("C#1", MidiMessage.NoteName(37));
        Assert.Equal("C3", MidiMessage.NoteName(60));
        Assert.Equal("C-2", MidiMessage.NoteName(0));
    }
}
