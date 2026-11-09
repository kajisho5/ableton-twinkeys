"""TwinKeys Bridge: an Ableton Live MIDI Remote Script (Live 11/12).

Lets the TwinKeys Mac app control Live and read its state over JSON/UDP on
127.0.0.1 only (commands in on port 47811, state out to port 47812).

Live loads this package from the User Library "Remote Scripts" folder and
calls create_instance(c_instance). The Live-specific import happens inside
create_instance so the other modules can be imported by the unit tests.
"""


def create_instance(c_instance):
    from .surface import TwinKeysBridge
    return TwinKeysBridge(c_instance)
