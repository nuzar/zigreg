//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const log = std.log;
const testing = std.testing;

const Status = enum {
    success,
    fail,
    normal,
};

const State = struct {
    // connectedStates: std.ArrayList(State),
    transitions: std.ArrayList(Transition),

    fn init(allocator: std.mem.Allocator) State {
        return State{
            .transitions = std.ArrayList(Transition).init(allocator),
        };
    }

    fn deinit(s: State) void {
        s.transitions.deinit();
    }

    fn isSuccessState(self: *State) bool {
        if (self.transitions.items.len == 0) {
            return true;
        }
        return false;
    }

    fn firstMatchingTransition(self: *State, input: u32) ?*State {
        for (self.transitions.items) |transition| {
            if (transition.predicate(input)) {
                return transition.to;
            }
        }

        return null;
    }
};

const Predicate = *const fn (input: u32) bool;

// TODO: can we make states const?
const Transition = struct {
    from: ?*State,
    to: ?*State,
    predicate: Predicate,
};

const Runner = struct {
    head: ?*State,
    current: ?*State,

    fn init(s: *State) Runner {
        return Runner{
            .head = s,
            .current = s,
        };
    }

    fn next(self: *Runner, input: u32) void {
        if (self.current) |s| {
            // move to next matching transition
            self.current = s.firstMatchingTransition(input);
        }
        return;
    }

    fn getStatus(self: *Runner) Status {
        if (self.current) |s| {
            if (s.isSuccessState()) {
                return Status.success;
            }
            return Status.normal;
        } else {
            return Status.fail;
        }
    }
};

fn char_eq(target: u32) (fn (u32) bool) {
    return struct {
        fn f(input: u32) bool {
            return input == target;
        }
    }.f;
}

test "hand made fsm" {
    const allocator = testing.allocator;

    const TestCase = struct {
        name: []const u8,
        input: []const u8,
        expectedStatus: Status,
    };

    const testcases = [_]TestCase{
        TestCase{
            .name = "empty string",
            .input = "",
            .expectedStatus = .normal,
        },
        TestCase{
            .name = "non matching string",
            .input = "x",
            .expectedStatus = .fail,
        },
        TestCase{
            .name = "matching string",
            .input = "abc",
            .expectedStatus = .success,
        },
        TestCase{
            .name = "partial matching string",
            .input = "ab",
            .expectedStatus = .normal,
        },
        TestCase{
            .name = "non matching unicode",
            .input = "不行",
            .expectedStatus = .fail,
        },
    };

    var startState = State.init(allocator);
    defer startState.deinit();
    var stateA = State.init(allocator);
    defer stateA.deinit();
    var stateB = State.init(allocator);
    defer stateB.deinit();
    var stateC = State.init(allocator);
    defer stateC.deinit();

    try startState.transitions.append(Transition{
        .from = null,
        .to = &stateA,
        .predicate = char_eq('a'),
    });
    try stateA.transitions.append(Transition{
        .from = null,
        .to = &stateB,
        .predicate = char_eq('b'),
    });
    try stateB.transitions.append(Transition{
        .from = null,
        .to = &stateC,
        .predicate = char_eq('c'),
    });

    var pass = true;
    for (testcases) |tc| {
        var runner = Runner.init(&startState);
        var utf8 = (try std.unicode.Utf8View.init(tc.input)).iterator();
        while (utf8.nextCodepoint()) |c| {
            const preState = runner.getStatus();
            runner.next(c);
            const postState = runner.getStatus();
            log.debug("{} -{}-> {}", .{ preState, c, postState });
        }
        const result = runner.getStatus();
        const ok = tc.expectedStatus == result;
        if (!ok) {
            log.err(
                "{s} failed: expected {any}, got {any}",
                .{ tc.name, tc.expectedStatus, result },
            );
            pass = false;
        }
    }
    try testing.expect(pass);
}
