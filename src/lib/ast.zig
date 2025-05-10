const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const fsm = @import("fsm.zig");
const lexer = @import("lexer.zig");

const CompileResult = struct { start: *fsm.State, end: *fsm.State };

pub const Node = union(enum) {
    literal: CharacterLiteral,
    group: Group,

    // FIXME: state holds pointer of node in predicator, rethink their deinit() logic
    pub fn compile(node: *Node, allocator: std.mem.Allocator) !CompileResult {
        return switch (node.*) {
            .literal => |*l| try l.compile(allocator),
            .group => |*g| try g.compile(allocator),
        };
    }

    fn is_composite(node: Node) bool {
        return switch (node) {
            .group => true,
            .literal => false,
        };
    }

    pub fn deinit(self: *Node) void {
        switch (self.*) {
            .group => |*g| g.deinit(),
            .literal => {},
        }
        // TODO: 是否要求所有复合节点实现 deinit() ?
        // if (self.is_composite()) {
        //     (&self).deinit();
        // }
    }
};

pub const CompositeNode = defineCompositeNode();

fn defineCompositeNode() type {
    const all_fields = @typeInfo(Node).@"union".fields;

    var i: usize = 0;
    var fields: [all_fields.len]std.builtin.Type.UnionField = undefined;
    for (all_fields) |field| {
        const node = @unionInit(Node, field.name, undefined);
        if (node.is_composite()) {
            fields[i] = field;
            i += 1;
        }
    }

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = null,
        .fields = fields[0..i],
        .decls = &.{},
    } });
}

pub fn composite(node: Node) ?CompositeNode {
    switch (node) {
        inline else => |v, tag| {
            // Use comptime to prune out invalid actions
            if (!comptime @unionInit(
                Node,
                @tagName(tag),
                undefined,
            ).is_composite()) return null;

            return @unionInit(
                CompositeNode,
                @tagName(tag),
                v,
            );
        },
    }
}

pub const Group = struct {
    childNodes: std.ArrayList(Node),

    pub fn init(allocator: std.mem.Allocator) Group {
        const children = std.ArrayList(Node).init(allocator);
        return Group{
            .childNodes = children,
        };
    }

    pub fn deinit(self: *Group) void {
        for (self.childNodes.items) |*node| {
            node.deinit();
        }
        self.childNodes.deinit();
    }

    pub fn append(self: *Group, node: Node) !void {
        try self.childNodes.append(node);
    }

    pub fn compile(self: *Group, allocator: std.mem.Allocator) Allocator.Error!CompileResult {
        const start = try fsm.State.init(allocator);
        var end: *fsm.State = start;

        for (self.childNodes.items) |*node| {
            const res = try node.compile(allocator);
            try end.merge(res.start);
            allocator.destroy(res.start);
            end = res.end;
        }

        return .{ .start = start, .end = end };
    }
};

test "compile group" {
    const allocator = testing.allocator;

    const chars = [_]u32{ 'a', 'b', 'c' };

    var group = Group{ .childNodes = std.ArrayList(Node).init(allocator) };
    for (chars) |char| {
        try group.append(Node{ .literal = CharacterLiteral{ .character = char } });
    }
    defer group.deinit();

    var result = try group.compile(allocator);
    defer result.start.deinit(allocator);

    var s = result.start;
    var charIdx: u32 = 0;
    while (!s.isSuccessState()) {
        try testing.expect(s.transitions.items[0].predicator.predicate(chars[charIdx]));
        charIdx += 1;
        s = s.transitions.items[0].to;
    }
}

pub const CharacterLiteral = struct {
    character: u32,

    pub fn compile(self: *CharacterLiteral, allocator: std.mem.Allocator) !CompileResult {
        var start = try fsm.State.init(allocator);
        const end = try fsm.State.init(allocator);

        try start.addTransition(end, self.Predicator());

        return .{ .start = start, .end = end };
    }

    fn Predicator(self: *CharacterLiteral) fsm.Predicator {
        return .{
            .ptr = self,
            .vtable = .{
                .predicate = predicate,
            },
        };
    }

    fn predicate(context: *anyopaque, input: u32) bool {
        const self: *CharacterLiteral = @ptrCast(@alignCast(context));
        return self.*.character == input;
    }
};

test "literal compile" {
    const allocator = testing.allocator;

    var literal = CharacterLiteral{ .character = 'x' };
    var result = try literal.compile(allocator);
    defer result.start.deinit(allocator);

    try testing.expectEqual(1, result.start.transitions.items.len);
    try testing.expectEqual(0, result.end.transitions.items.len);
    try testing.expect(result.start.transitions.items[0].predicator.predicate('x'));
    try testing.expect(!result.start.transitions.items[0].predicator.predicate('y'));
}
