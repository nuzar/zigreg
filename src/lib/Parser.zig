const std = @import("std");
const log = std.log;

const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

const Self = @This();

pub fn init() Self {
    const p = Self{};
    return p;
}

pub fn deinit(_: *Self) void {}

pub fn parse(_: Self, allocator: std.mem.Allocator, tokens: []lexer.Token) !ast.Node {
    var root = ast.Node{ .group = ast.Group.init(allocator) };

    for (tokens) |tk| {
        switch (tk.symbol) {
            .character => {
                const node = ast.Node{ .literal = .{ .character = tk.letter } };
                try root.group.append(node);
            },
            else => {
                // TODO
                unreachable;
            },
        }
    }

    return root;
}

test "parse simple string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "aBc";
    const expectedNodes = [_]ast.Node{
        .{ .literal = .{ .character = 'a' } },
        .{ .literal = .{ .character = 'B' } },
        .{ .literal = .{ .character = 'c' } },
    };

    const tokens = try lexer.lex(input, allocator);
    defer allocator.free(tokens);

    var parser = Self.init();
    defer parser.deinit();
    var result = try parser.parse(allocator, tokens);
    defer result.deinit();

    switch (result) {
        .literal => unreachable,
        .group => |g| {
            try testing.expectEqualSlices(ast.Node, expectedNodes[0..], g.childNodes.items);
        },
    }
}
