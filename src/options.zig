const c = @import("c.zig");
const err = @import("error.zig");

pub fn disableDeviceDiscovery() err.Error!void {
    try err.failable(c.libusb_set_option(null, c.LIBUSB_OPTION_NO_DEVICE_DISCOVERY));
}

pub const LogLevel = enum(u8) {
    None = 0,
    Error,
    Warning,
    Info,
    Debug,
};

pub fn setLogLevel(log_level: LogLevel) err.Error!void {
    try err.failable(c.libusb_set_option(null, c.LIBUSB_OPTION_LOG_LEVEL, @intFromEnum(log_level)));
}
