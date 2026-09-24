// Test-only injection into the real preview buffer; never linked into Axial.
#include "../app/bridge.cpp"
extern "C" void AxialTestInput(double value) {
    sn::Event event;event.kind=sn::Kind::motion;event.device=1;
    event.vendor=0x046d;event.product=0xc627;event.received=sn::now();
    event.axes[0]=int16_t(value);event.axes[3]=int16_t(value);
    preview.receive(event);
}
