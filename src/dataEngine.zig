const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("ziqlTokenizer.zig").Tokenizer;

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const DataEngine = struct {
    arena: std.heap.ArenaAllocator,
    allocator: Allocator,
    dir: std.fs.Dir, // The path to the DATA folder
    max_file_size: usize = 1e+8, // 100mb

    pub fn init(allocator: Allocator) DataEngine {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const dir = std.fs.cwd().openDir("ZipponDB/DATA", .{}) catch @panic("Error opening ZipponDB/DATA");
        return DataEngine{
            .arena = arena,
            .allocator = arena.allocator(),
            .dir = dir,
        };
    }

    pub fn deinit(self: *DataEngine) void {
        self.arena.deinit();
    }

    /// Iter over all file and get the max name and return the value of it as usize
    /// So for example if there is 1.zippondata and 2.zippondata it return 2.
    fn maxFileIndex(_: *DataEngine, map: *std.StringHashMap(std.fs.File.Stat)) usize {
        var iter = map.keyIterator();
        var index_max: usize = 0;
        while (iter.next()) |key| {
            if (std.mem.eql(u8, key.*, "main.zippondata")) continue;
            var iter_file_name = std.mem.tokenize(u8, key.*, ".");
            const num_str = iter_file_name.next().?;
            const num: usize = std.fmt.parseInt(usize, num_str, 10) catch @panic("Error parsing file name into usize");
            if (num > index_max) index_max = num;
        }
        return index_max;
    }

    /// Use a filename in the format 1.zippondata and return the 1
    fn fileName2Index(_: *DataEngine, file_name: []const u8) usize {
        var iter_file_name = std.mem.tokenize(u8, file_name, ".");
        const num_str = iter_file_name.next().?;
        const num: usize = std.fmt.parseInt(usize, num_str, 10) catch @panic("Couln't parse the int of a zippondata file.");
        return num;
    }

    /// Add an UUID at a specific index of a file
    /// Used when some data are deleted from previous zippondata files and are now bellow the file size limit
    fn appendToLineAtIndex(self: *DataEngine, file: std.fs.File, index: usize, str: []const u8) !void {
        const buffer = try self.allocator.alloc(u8, 1024 * 100);
        defer self.allocator.free(buffer);

        var reader = file.reader();

        var line_num: usize = 1;
        while (try reader.readUntilDelimiterOrEof(buffer, '\n')) |_| {
            if (line_num == index) {
                try file.seekBy(-1);
                try file.writer().print("{s}  ", .{str});
                return;
            }
            line_num += 1;
        }
    }

    /// Return a map of file path => Stat; for one struct and member name
    /// E.g. for User & name
    fn getFilesStat(self: *DataEngine, struct_name: []const u8, member_name: []const u8) !*std.StringHashMap(std.fs.File.Stat) {
        const buffer = try self.allocator.alloc(u8, 1024); // Adjust the size as needed
        defer self.allocator.free(buffer);

        const path = try std.fmt.bufPrint(buffer, "{s}{s}/{s}", .{ self.path.basename(), struct_name, member_name });

        var file_map = std.StringHashMap(std.fs.File.Stat).init(self.allocator);

        const member_dir = self.path.openDir(path, .{ .iterate = true }) catch @panic("Error opening struct directory");

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != std.fs.Dir.Entry.Kind.file) continue;

            const file_stat = member_dir.statFile(entry.name) catch @panic("Error getting stat of a file");

            file_map.put(entry.name, file_stat) catch @panic("Error adding stat to map");
        }

        return &file_map;
    }

    /// Use the map of file stat to find the first file with under the bytes limit.
    /// return the name of the file. If none is found, return null.
    fn getFirstUsableFile(self: *DataEngine, map: *std.StringHashMap(std.fs.File.Stat)) ?[]const u8 {
        var iter = map.keyIterator();
        while (iter.next()) |key| {
            if (std.mem.eql(u8, key.*, "main.zippondata")) continue;
            if (map.get(key.*).?.size < self.max_file_size) return key.*;
        }
        return null;
    }
};
