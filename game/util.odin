package game
import "core:fmt"

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