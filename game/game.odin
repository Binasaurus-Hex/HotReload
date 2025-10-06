package game

import "core:fmt"
import "core:os"
import "core:math/linalg"
import rl "vendor:raylib"
import sa "core:container/small_array"

@export
init_window :: proc(){
    rl.InitWindow(700, 600, "Hello Bingo")
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

EntityFeature :: enum {
    PlayerControl
}

Entity :: struct {
    features: bit_set[EntityFeature],
    position, facing: [2]f32
}

GameState :: struct {
    game_over: bool,
    entities: sa.Small_Array(200, Entity),
    initialized: bool,
}

state: GameState

get_default_state :: proc() -> GameState {
    state: GameState

    for i in 0..<10 {
        // enemies
        sa.append(&state.entities, Entity {
            position = { f32(i) * 60, 200 }
        })

        sa.append(&state.entities, Entity {
            position = { 0, 0 },
            features = {.PlayerControl }
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

    camera: rl.Camera2D

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

        camera.zoom = 1
        camera.offset = { f32(rl.GetRenderWidth() ), f32(rl.GetRenderHeight()) } / 2

        delta := rl.GetFrameTime()

        rl.BeginMode2D(camera)

        for &entity in sa.slice(&state.entities){
            color := rl.RED
            if .PlayerControl in entity.features {
                entity.position += movement() * delta * 400
                camera.target = entity.position
                color = rl.WHITE

                for &other in sa.slice(&state.entities){
                    if .PlayerControl in other.features do continue
                    if &other == &entity do continue
                    if rl.CheckCollisionCircles(entity.position, 30, other.position, 30) {
                        state.game_over = true
                    }
                }
            }
            rl.DrawCircleV(entity.position, 30, color)
        }

        rl.EndMode2D()

        if state.game_over {
            rl.DrawText("game over", 350, 300, 20, rl.BLUE)
        }


        // update
        if rl.IsKeyPressed(.TAB){
            state = get_default_state()
        }

        rl.EndDrawing()
    }
    return
}


// util

movement :: proc() -> [2]f32 {
    x := int(rl.IsKeyDown(.D)) - int(rl.IsKeyDown(.A))
    y := int(rl.IsKeyDown(.S)) - int(rl.IsKeyDown(.W))
    return linalg.normalize0([2]f32 { f32(x), f32(y) })
}

















// deferred drawing
DrawCircle :: struct {
    centre: [2]f32,
    radius: f32,
    color: rl.Color
}

draw_circle :: proc(centre: [2]f32, radius: f32, color: rl.Color){
    // sa.append(&state.draw_commands, DrawCircle { centre, radius, color })
}

DrawLine :: struct {
    from, to: [2]f32,
    color: rl.Color
}

draw_line :: proc(from, to: [2]f32, color: rl.Color){
    // sa.append(&state.draw_commands, DrawLine { from, to, color })
}

DrawCommand :: union {
    DrawCircle, DrawLine
}