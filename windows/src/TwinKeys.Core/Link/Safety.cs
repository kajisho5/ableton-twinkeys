namespace TwinKeys.Core;

/// <summary>When All Notes Off is sent, and where to (port of Safety.swift).</summary>
public enum SafetyTrigger { PanicButton, AppWillQuit, ConnectionLost, ManualDisconnect, PeerSaidBye, SendingTurnedOff, KeyCaptureTurnedOff }

public enum SafetyLocal
{
    /// <summary>Leave this computer's port alone.</summary>
    None,
    /// <summary>Turn off only notes that came from the peer.</summary>
    NotesFromPeer,
    /// <summary>Turn off notes played by this computer's own keys.</summary>
    NotesFromKeys,
    /// <summary>All Notes Off (CC 123 on every channel) plus note-offs for every tracked note.</summary>
    All,
}

/// <summary><paramref name="Remote"/>: tell the connected peer (only if there is one).</summary>
public readonly record struct SafetyPlan(SafetyLocal Local, bool Remote);

public static class Safety
{
    public static SafetyPlan Plan(SafetyTrigger trigger, bool connected) => trigger switch
    {
        SafetyTrigger.PanicButton or SafetyTrigger.AppWillQuit or SafetyTrigger.ManualDisconnect => new(SafetyLocal.All, connected),
        // Our keys stop producing notes: end the ones they started, on both computers.
        SafetyTrigger.SendingTurnedOff or SafetyTrigger.KeyCaptureTurnedOff => new(SafetyLocal.NotesFromKeys, connected),
        // The peer is gone. Notes it started here must not hang, but notes played here keep sounding.
        _ => new(SafetyLocal.NotesFromPeer, false),
    };
}
