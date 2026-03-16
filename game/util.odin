package game
import "core:fmt"
import "core:path/filepath"
import "core:path/slashpath"
import os "core:os/os2"
import rl "vendor:raylib"
import "core:math/linalg"
import "vendor:raylib/rlgl"

StaticString :: struct(buffer_size: int){
    buffer: [buffer_size]u8,
    length: int
}

static_to_string :: proc(static_string: ^StaticString($T)) -> string {
    return string(static_string.buffer[:static_string.length])
}

write_to_static :: proc(static_string: ^StaticString($T), value: string){
    assert(len(static_string.buffer) > len(value), fmt.tprintf("string '{}' too long for buffer", value))
    fmt.bprint(static_string.buffer[:], value)
    static_string.length = len(value)
}

append_to_static :: proc(static_string: ^StaticString($T), value: string){
    fmt.bprint(static_string.buffer[static_string.length:], value)
    static_string.length += len(value)
}

equal_to_static :: proc(static_string: ^StaticString($T), value: string) -> bool {
    return static_to_string(static_string) == value
}

// timer

Timer :: struct {
    time: f32,
    elapsed: f32,

    loop: bool,
    running: bool
}

timer_try_start :: proc(timer: ^Timer, time: f32){
    if timer.running do return
    timer^ = timer_start(time, false)
}

timer_start :: proc(time: f32, loop: bool = true) -> Timer {
    return Timer {time, 0, loop, true }
}

timer_update :: proc(timer: ^Timer, delta: f32) -> (complete: bool){
    if !timer.running {
        return
    }
    timer.elapsed += delta
    if timer.elapsed > timer.time {
        complete = true
        timer.elapsed = 0
        if !timer.loop {
            timer.running = false
        }
    }
    return
}

// rendering

draw_textured_rect :: proc(texture: rl.Texture, rect: rl.Rectangle){
    source := rl.Rectangle {0, 0, f32(texture.width), f32(texture.height)}
    rl.DrawTexturePro(texture, source, rect, {}, 0, rl.WHITE)
}


file_wait :: proc(fullpath: string){
    dir, name := filepath.split(fullpath)
    new := slashpath.join({dir, "______"}, context.temp_allocator)
    for os.rename(fullpath, new) != nil {
    }
    os.rename(new, fullpath)
}

damp :: proc(a, b: $T, lambda, delta: $E) -> T {
    return linalg.lerp(a, b, 1 - linalg.exp(-lambda * delta))
}

fast_rotate_vector :: proc "contextless" (q, v: [2]f32) -> [2]f32 {
    return {q.x * v.x - q.y * v.y, q.y * v.x + q.x * v.y}
}

// reimplementation of raylib function in odin, with some speed improvements such as using a facing instead of a rotation
// Draw a part of a texture (defined by a rectangle) with 'pro' parameters
// NOTE: origin is relative to destination rectangle size
DrawTexturePro :: proc "contextless" (texture: rl.Texture, source, dest: rl.Rectangle, origin, facing: rl.Vector2, tint: rl.Color){
    if texture.id == 0 do return

    dest := dest
    source := source

    width, height := f32(texture.width), f32(texture.height)

    top_left := [2]f32{dest.x, dest.y} - origin
    top_right := top_left + [2]f32{ dest.width, 0 }
    bottom_left := top_left + { 0, dest.height }
    bottom_right := top_left + { dest.width, dest.height }

    position := [2]f32 { dest.x, dest.y }

    facing := facing
    if facing == {} {
        facing = {1, 0}
    }

    top_left = fast_rotate_vector(facing, top_left - position) + position
    top_right = fast_rotate_vector(facing, top_right - position) + position
    bottom_left = fast_rotate_vector(facing, bottom_left - position) + position
    bottom_right = fast_rotate_vector(facing, bottom_right - position) + position

    rlgl.SetTexture(texture.id);
    rlgl.Begin(rlgl.QUADS);

        rlgl.Color4ub(tint.r, tint.g, tint.b, tint.a);
        rlgl.Normal3f(0.0, 0.0, 1.0);                          // Normal vector pointing towards viewer

        // Top-left corner for texture and quad
        rlgl.TexCoord2f(source.x/width, source.y/height)
        rlgl.Vertex2f(top_left.x, top_left.y);

        rlgl.TexCoord2f(source.x/width, (source.y + source.height)/height)
        rlgl.Vertex2f(bottom_left.x, bottom_left.y)

        rlgl.TexCoord2f((source.x + source.width)/width, (source.y + source.height)/height)
        rlgl.Vertex2f(bottom_right.x, bottom_right.y)

        rlgl.TexCoord2f((source.x + source.width)/width, source.y/height)
        rlgl.Vertex2f(top_right.x, top_right.y);

    rlgl.End();
    rlgl.SetTexture(0);
}