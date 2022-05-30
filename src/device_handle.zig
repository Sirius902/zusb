const c = @import("c.zig");
const std = @import("std");
const Context = @import("context.zig").Context;
const Device = @import("device.zig").Device;
const fromLibusb = @import("constructor.zig").fromLibusb;

const err = @import("error.zig");

pub const DeviceHandle = struct {
    ctx: *Context,
    raw: *c.libusb_device_handle,
    interfaces: u256,

    pub fn deinit(self: DeviceHandle) void {
        var iface: u9 = 0;
        while (iface < 256) : (iface += 1) {
            if ((self.interfaces >> @truncate(u8, iface)) & 1 == 1) {
                _ = c.libusb_release_interface(self.raw, @as(c_int, iface));
            }
        }

        c.libusb_close(self.raw);
    }

    pub fn claimInterface(self: *DeviceHandle, iface: u8) err.Error!void {
        try err.failable(c.libusb_claim_interface(self.raw, @as(c_int, iface)));
        self.interfaces |= @as(u256, 1) << iface;
    }

    pub fn releaseInterface(self: *DeviceHandle, iface: u8) err.Error!void {
        try err.failable(c.libusb_release_interface(self.raw, @as(c_int, iface)));
        self.interfaces &= ~(@as(u256, 1) << iface);
    }

    pub fn device(self: DeviceHandle) Device {
        return fromLibusb(Device, .{ self.ctx, c.libusb_get_device(self.raw).? });
    }

    pub fn writeControl(
        self: DeviceHandle,
        requestType: u8,
        request: u8,
        value: u16,
        index: u16,
        buf: []const u8,
        timeout_ms: u64,
    ) (error{Overflow} || err.Error)!usize {
        if (requestType & c.LIBUSB_ENDPOINT_DIR_MASK != c.LIBUSB_ENDPOINT_OUT) {
            return error.InvalidParam;
        }

        const res = c.libusb_control_transfer(
            self.raw,
            requestType,
            request,
            value,
            index,
            @intToPtr([*c]u8, @ptrToInt(buf.ptr)),
            std.math.cast(u16, buf.len) orelse return error.Overflow,
            std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
        );

        if (res < 0) {
            return err.errorFromLibusb(res);
        } else {
            return @intCast(usize, res);
        }
    }

    pub fn readInterrupt(
        self: DeviceHandle,
        endpoint: u8,
        buf: []u8,
        timeout_ms: u64,
    ) (error{Overflow} || err.Error)!usize {
        if (endpoint & c.LIBUSB_ENDPOINT_DIR_MASK != c.LIBUSB_ENDPOINT_IN) {
            return error.InvalidParam;
        }

        var transferred: c_int = undefined;

        const ret = c.libusb_interrupt_transfer(
            self.raw,
            endpoint,
            buf.ptr,
            std.math.cast(c_int, buf.len) orelse return error.Overflow,
            &transferred,
            std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
        );

        if (ret == 0 or ret == c.LIBUSB_ERROR_INTERRUPTED and transferred > 0) {
            return @intCast(usize, transferred);
        } else {
            return err.errorFromLibusb(ret);
        }
    }

    pub fn writeInterrupt(
        self: DeviceHandle,
        endpoint: u8,
        buf: []const u8,
        timeout_ms: u64,
    ) (error{Overflow} || err.Error)!usize {
        if (endpoint & c.LIBUSB_ENDPOINT_DIR_MASK != c.LIBUSB_ENDPOINT_OUT) {
            return error.InvalidParam;
        }

        var transferred: c_int = undefined;

        const ret = c.libusb_interrupt_transfer(
            self.raw,
            endpoint,
            @intToPtr([*c]u8, @ptrToInt(buf.ptr)),
            std.math.cast(c_int, buf.len) orelse return error.Overflow,
            &transferred,
            std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
        );

        if (ret == 0 or ret == c.LIBUSB_ERROR_INTERRUPTED and transferred > 0) {
            return @intCast(usize, transferred);
        } else {
            return err.errorFromLibusb(ret);
        }
    }
};
