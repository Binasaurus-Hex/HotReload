package game

import "core:fmt"
import "core:os"
import "core:math/linalg"
import rl "vendor:raylib"
import sa "core:container/small_array"

@export
init_window :: proc(){
    rl.InitWindow(800, 600, "Hello Bingo")
    rl.SetWindowState({.WINDOW_RESIZABLE})
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

@export
run :: proc() -> (reload: bool) {

    initial_mod_time, mod_time_error := os.last_write_time_by_name(#file)
    assert(mod_time_error == os.ERROR_NONE)


    if !state.initialized {
        state = get_default_state()
    }

    for !rl.WindowShouldClose(){
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        // check file reload
        {
            mod_time, mod_time_error := os.last_write_time_by_name(#file)
            if mod_time_error == os.ERROR_NONE {
                if mod_time > initial_mod_time {
                    reload = true
                    break
                }
            }
        }

        if rl.IsKeyPressed(.TAB){
            state = get_default_state()
        }

        movement :: proc() -> [2]f32 {
            x := int(rl.IsKeyDown(.D)) - int(rl.IsKeyDown(.A))
            y := int(rl.IsKeyDown(.S)) - int(rl.IsKeyDown(.W))
            return linalg.normalize0([2]f32 { f32(x), f32(y) })
        }

        {
            offset: int
            if rl.IsKeyPressed(.ONE) do offset = -1
            if rl.IsKeyPressed(.TWO) do offset = +1
            state.selected_entity += offset
            state.selected_entity %%= sa.len(state.entities)
        }

        for &entity, i in sa.slice(&state.entities){
            selected := i == state.selected_entity
            if selected {
                entity.position += movement() * rl.GetFrameTime() * 400
                entity.facing = linalg.normalize0(rl.GetMousePosition() - entity.position)
            }
            rl.DrawCircleV(entity.position, 30, rl.BLUE if !selected else rl.WHITE)
            rl.DrawLineV(entity.position, entity.position + entity.facing * 70, rl.GREEN)
        }

        rl.EndDrawing()
    }
    return
}
