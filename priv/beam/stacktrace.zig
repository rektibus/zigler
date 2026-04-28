const std = @import("std");
const builtin = @import("builtin");
const beam = @import("beam.zig");
const options = @import("options.zig");

const SelfInfo = std.debug.SelfInfo;

fn make_empty_trace_item(opts: anytype) beam.term {
    return beam.make(.{
        .source_location = null,
        .symbol_name = null,
        .compile_unit_name = null,
    }, opts);
}

fn make_trace_item(debug_info: *SelfInfo, address: usize, opts: anytype) beam.term {
    var symbol_fallback_allocator = std.heap.stackFallback(@sizeOf(std.debug.Symbol) + @alignOf(std.debug.Symbol) - 1, std.debug.getDebugInfoAllocator());
    const symbol_allocator = symbol_fallback_allocator.get();
    var symbols = std.ArrayList(std.debug.Symbol).initCapacity(symbol_allocator, 1) catch return make_empty_trace_item(opts);
    defer symbols.deinit(symbol_allocator);

    var text_arena = std.heap.ArenaAllocator.init(std.debug.getDebugInfoAllocator());
    defer text_arena.deinit();

    debug_info.getSymbols(
        std.Options.debug_io,
        symbol_allocator,
        text_arena.allocator(),
        address,
        false,
        &symbols,
    ) catch return make_empty_trace_item(opts);

    if (symbols.items.len == 0) return make_empty_trace_item(opts);
    const symbol_info = symbols.items[0];

    return beam.make(.{
        .source_location = symbol_info.source_location,
        .symbol_name = symbol_info.name,
        .compile_unit_name = symbol_info.compile_unit_name,
    }, opts);
}

pub fn to_term(stacktrace: *std.builtin.StackTrace, opts: anytype) beam.term {
    if (builtin.strip_debug_info) return beam.make(.nil, opts);

    const debug_info = std.debug.getSelfDebugInfo() catch return beam.make(.nil, opts);
    // NOTE: we should never deinit the debug_info, as it doesn't change over the execution of
    // the process.  It will be stored as a "global object".

    var frame_index: usize = 0;
    var frames_left: usize = @min(stacktrace.index, stacktrace.instruction_addresses.len);
    var stacktrace_term = beam.make_empty_list(opts);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stacktrace.instruction_addresses.len;
    }) {
        const return_address = stacktrace.instruction_addresses[frame_index];
        const new_trace_item = make_trace_item(debug_info, return_address -| 1, opts);
        stacktrace_term = beam.make_list_cell(new_trace_item, stacktrace_term, opts);
    }
    return stacktrace_term;
}
