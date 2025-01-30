// For when I move to a single file
// How I see it is that I have some kind of fileVar that keep a position and type
// When I want to read the value, I read the file then convert it back
// I can do something similar but with a chunck of data after
// Like a start position and size, like memory but for file
// The point being giving more size when I modify thing to prevent rewritting everything

const std = @import("std");
const zid = @import("ZipponData");

pub fn fileVar(comptime T: type) type {
    return struct {
        const Self = @This();

        position: usize,
        file: *std.fs.File,
        T: type = T,

        pub fn init(position: usize, file: *std.fs.File) Self {
            return .{
                .position = position,
                .file = file,
            };
        }

        pub fn read(self: Self) !T {
            try self.file.seekTo(self.position);
            self.file.reader().readBytesNoEof(@sizeOf(T));
        }
    };
}

// I also need some kind of file arena to store data. Those arena would act like files
// In SQLite, this is call page I think. Each can either hold data of a unique struct or multiple variable.

pub const fileBlock = struct {
    position: usize,
    size: usize,
};
