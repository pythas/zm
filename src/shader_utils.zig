const std = @import("std");
const zgpu = @import("zgpu");

const common_shader_code = @embedFile("shaders/common.wgsl");

pub fn createShaderModuleWithCommon(
    device: zgpu.wgpu.Device,
    shader_code: []const u8,
    entry_point: []const u8,
) zgpu.wgpu.ShaderModule {
    const combined_code = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}\n\n{s}", .{ common_shader_code, shader_code }) catch @panic("Failed to allocate shader code");
    defer std.heap.page_allocator.free(combined_code);

    const entry_point_z = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{entry_point}) catch @panic("Failed to allocate entry point");
    defer std.heap.page_allocator.free(entry_point_z);

    return zgpu.createWgslShaderModule(device, combined_code.ptr, entry_point_z.ptr);
}

