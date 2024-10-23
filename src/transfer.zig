const c = @import("c.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const DeviceHandle = @import("device_handle.zig").DeviceHandle;
const PacketDescriptor = @import("packet_descriptor.zig").PacketDescriptor;
const PacketDescriptors = @import("packet_descriptor.zig").PacketDescriptors;

const err = @import("error.zig");

pub const TransferFlags = packed struct(u8) {
    shortNotOk: bool = false,
    freeBuffer: bool = false,
    freeTransfer: bool = false,
    addZeroPacket: bool = false,
    _padding: u4 = 0,
};

pub const TransferStatus = enum(u8) {
    Completed = 0,
    Error,
    Timeout,
    Cancelled,
    Stall,
    Overflow,
    NoDevice,
    _,
};

fn transferStatusFromLibusb(transfer_status: c_uint) TransferStatus {
    return @enumFromInt(transfer_status);
}

pub fn Transfer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        buf: []u8,
        transfer: *c.libusb_transfer,
        callback: *const fn (*Self) void,
        user_data: ?*T,
        active: bool = false,

        pub fn deinit(self: *Self) void {
            if (self.active) {
                @panic("Can't deinit an active transfer");
            }
            const flags = self.transferFlags();
            if (!flags.freeTransfer) {
                c.libusb_free_transfer(self.transfer);
            }
            self.allocator.free(self.buf);
            self.allocator.destroy(self);
        }

        pub fn transferFlags(self: Self) TransferFlags {
            return @bitCast(self.transfer.*.flags);
        }

        pub fn transferStatus(self: Self) TransferStatus {
            return transferStatusFromLibusb(self.transfer.*.status);
        }

        pub fn isoPackets(self: Self) PacketDescriptors {
            const num_iso_packets: usize = @intCast(self.transfer.*.num_iso_packets);
            return PacketDescriptors.init(self.transfer, self.transfer.*.iso_packet_desc()[0..num_iso_packets]);
        }

        pub fn submit(self: *Self) err.Error!void {
            self.active = true;
            try err.failable(c.libusb_submit_transfer(self.transfer));
        }

        pub fn cancel(self: *Self) err.Error!void {
            try err.failable(c.libusb_cancel_transfer(self.transfer));
        }

        pub fn getData(self: Self) []u8 {
            const length = std.math.cast(usize, self.transfer.actual_length) orelse @panic("Buffer length too large");
            return self.transfer.buffer[0..length];
        }

        pub fn setData(self: *Self, data: []const u8) void {
            @memcpy(self.buf, data);
            self.transfer.length = std.math.cast(c_int, data.len) orelse @panic("Buffer length too large");
        }

        pub fn isActive(self: Self) bool {
            return self.active;
        }

        pub fn fillIsochronous(
            allocator: Allocator,
            handle: *DeviceHandle,
            endpoint: u8,
            packet_size: u16,
            num_packets: u16,
            callback: *const fn (*Self) void,
            user_data: *T,
            timeout: u64,
            flags: TransferFlags,
        ) !*Self {
            const buf = try allocator.alloc(u8, packet_size * num_packets);
            const opt_transfer: ?*c.libusb_transfer = c.libusb_alloc_transfer(num_packets);

            if (opt_transfer) |transfer| {
                const self = try allocator.create(Self);
                self.* = .{
                    .allocator = allocator,
                    .transfer = transfer,
                    .callback = callback,
                    .user_data = user_data,
                    .buf = buf,
                    .active = true,
                };

                transfer.*.dev_handle = handle.raw;
                transfer.*.endpoint = endpoint;
                transfer.*.type = c.LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
                transfer.*.buffer = buf.ptr;
                transfer.*.length = std.math.cast(c_int, buf.len) orelse @panic("Length too large");
                transfer.*.num_iso_packets = std.math.cast(c_int, num_packets) orelse @panic("Number of packets too large");
                transfer.*.callback = callbackRaw;
                transfer.*.user_data = @ptrCast(self);
                transfer.*.timeout = std.math.cast(c_uint, timeout) orelse @panic("Timeout too large");
                transfer.*.flags = @bitCast(flags);

                c.libusb_set_iso_packet_lengths(transfer, packet_size);

                return self;
            } else {
                return error.OutOfMemory;
            }
        }

        pub fn fillInterrupt(
            allocator: Allocator,
            handle: *DeviceHandle,
            endpoint: u8,
            buffer_size: usize,
            callback: *const fn (*T, []const u8) anyerror!void,
            user_data: *T,
            timeout: u64,
            flags: TransferFlags,
        ) (Allocator.Error || err.Error)!*Self {
            const buf = try allocator.alloc(u8, buffer_size);

            const opt_transfer: ?*c.libusb_transfer = c.libusb_alloc_transfer(0);

            if (opt_transfer) |transfer| {
                const self = try allocator.create(Self);
                self.* = .{
                    .allocator = allocator,
                    .transfer = transfer,
                    .user_data = user_data,
                    .buf = buf,
                    .callback = callback,
                    .active = true,
                };

                transfer.*.dev_handle = handle.raw;
                transfer.*.endpoint = endpoint;
                transfer.*.type = c.LIBUSB_TRANSFER_TYPE_INTERRUPT;
                transfer.*.timeout = std.math.cast(c_uint, timeout) orelse @panic("Timeout too large");
                transfer.*.buffer = buf.ptr;
                transfer.*.length = std.math.cast(c_int, buf.len) orelse @panic("Length too large");
                transfer.*.user_data = @ptrCast(self);
                transfer.*.callback = callbackRaw;
                transfer.*.flags = @bitCast(flags);

                return self;
            } else {
                return error.OutOfMemory;
            }
        }

        pub fn fillBulk(
            allocator: Allocator,
            handle: *DeviceHandle,
            endpoint: u8,
            buffer_size: usize,
            callback: *const fn (*Self) void,
            user_data: ?*T,
            timeout: u64,
            flags: TransferFlags,
        ) (Allocator.Error || err.Error)!*Self {
            const buf = try allocator.alloc(u8, buffer_size);

            const opt_transfer: ?*c.libusb_transfer = c.libusb_alloc_transfer(0);

            if (opt_transfer) |transfer| {
                const self = try allocator.create(Self);
                self.* = .{
                    .allocator = allocator,
                    .transfer = transfer,
                    .user_data = user_data,
                    .buf = buf,
                    .callback = callback,
                    .active = true,
                };

                transfer.*.dev_handle = handle.raw;
                transfer.*.endpoint = endpoint;
                transfer.*.type = c.LIBUSB_TRANSFER_TYPE_BULK;
                transfer.*.timeout = std.math.cast(c_uint, timeout) orelse @panic("Timeout too large");
                transfer.*.buffer = buf.ptr;
                transfer.*.length = std.math.cast(c_int, buf.len) orelse @panic("Length too large");
                transfer.*.user_data = @ptrCast(self);
                transfer.*.callback = callbackRaw;
                transfer.*.flags = @bitCast(flags);

                return self;
            } else {
                return error.OutOfMemory;
            }
        }

        fn callbackRaw(transfer: [*c]c.libusb_transfer) callconv(.C) void {
            const self: *Self = @alignCast(@ptrCast(transfer.*.user_data.?));
            self.active = false;
            self.callback(self);
        }
    };
}
