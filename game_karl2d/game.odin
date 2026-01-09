package game

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:math/linalg"
import "core:time"
import k2 "../karl2d"
import sa "core:container/small_array"
import "base:runtime"

@export
init_window :: proc() -> rawptr {
    return k2.init(800, 600, "Hello Bingo", {.Windowed_Resizable})
}

@export
set_window_state :: proc(state: rawptr){
    k2.set_internal_state(transmute(^k2.State)state)
}

@export
save :: proc() -> []u8 {
    return serialize(&state)
}

@export
load :: proc(data: []u8) {
    deserialize(&state, data)
}

Entity :: struct {
    position, facing: [2]f32
}

GameState :: struct {
    selected_entity: int,
    entities: sa.Small_Array(200, Entity),
    initialized: bool,
}

state: GameState

get_default_state :: proc() -> GameState {
    state: GameState

    for i in 0..<10 {
        sa.append(&state.entities, Entity {
            position = { 60 + f32(i) * 70, 200 }
        })
    }

    state.initialized = true
    return state
}

check_reload :: proc() -> bool {

    @static start_time: os.File_Time

    if start_time == os.File_Time(0) {
        file_time, err := os.last_write_time_by_name(#file)
        assert(err == nil)
        start_time = file_time
    }

    files, read_err := os2.read_all_directory_by_path(#directory, context.temp_allocator)
    assert(read_err == nil, fmt.tprint(read_err))
    for file in files {
        new_time := os.last_write_time_by_name(file.fullpath) or_continue
        if new_time > start_time do return true
    }
    return false
}

@export
run :: proc() -> (reload: bool) {

    if !state.initialized {
        state = get_default_state()
    }

    for !k2.shutdown_wanted(){
        k2.new_frame()
        k2.process_events()
        k2.clear(k2.BLACK)

        if check_reload(){
            return true
        }

        if k2.key_went_down(.Tab){
            state = get_default_state()
        }

        movement :: proc() -> [2]f32 {
            x := int(k2.key_is_held(.D)) - int(k2.key_is_held(.A))
            y := int(k2.key_is_held(.S)) - int(k2.key_is_held(.W))
            return linalg.normalize0([2]f32 { f32(x), f32(y) })
        }

        {
            offset: int
            if k2.key_went_down(.N1) do offset = -1
            if k2.key_went_down(.N2) do offset = +1
            state.selected_entity += offset
            state.selected_entity %%= sa.len(state.entities)
        }

        for &entity, i in sa.slice(&state.entities){
            selected := i == state.selected_entity
            if selected {
                entity.position += movement() * k2.get_frame_time() * 600
                entity.facing = linalg.normalize0(k2.get_mouse_position() - entity.position)
            }
            k2.draw_circle(entity.position, 30, k2.RED if !selected else k2.WHITE)
            k2.draw_line(entity.position, entity.position + entity.facing * 70, 2, k2.GREEN)
        }

        k2.present()
        free_all(context.temp_allocator)
    }
    return false
}
