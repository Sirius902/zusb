const c = @import("c.zig");
const ConfigDescriptor = @import("config_descriptor.zig").ConfigDescriptor;
const Context = @import("context.zig").Context;
const DeviceDescriptor = @import("device_descriptor.zig").DeviceDescriptor;
const DeviceHandle = @import("device_handle.zig").DeviceHandle;
const fromLibusb = @import("constructor.zig").fromLibusb;

const err = @import("error.zig");

pub const Device = struct {
    ctx: *Context,
    raw: *c.libusb_device,

    pub fn deinit(self: Device) void {
        _ = c.libusb_unref_device(self.raw);
    }

    pub fn deviceDescriptor(self: Device) err.Error!DeviceDescriptor {
        var descriptor: c.libusb_device_descriptor = undefined;

        try err.failable(c.libusb_get_device_descriptor(
            self.raw,
            &descriptor,
        ));

        return DeviceDescriptor{ .descriptor = descriptor };
    }

    pub fn configDescriptor(self: Device, config_index: u8) err.Error!ConfigDescriptor {
        var descriptor: ?*c.libusb_config_descriptor = null;

        try err.failable(c.libusb_get_config_descriptor(
            self.raw,
            config_index,
            &descriptor,
        ));

        return ConfigDescriptor{ .descriptor = descriptor.? };
    }

    pub fn busNumber(self: Device) u8 {
        return c.libusb_get_bus_number(self.raw);
    }

    pub fn address(self: Device) u8 {
        return c.libusb_get_device_address(self.raw);
    }

    pub fn open(self: Device) err.Error!DeviceHandle {
        var handle: ?*c.libusb_device_handle = null;
        try err.failable(c.libusb_open(self.raw, &handle));

        return fromLibusb(DeviceHandle, .{ self.ctx, handle.? });
    }
};
