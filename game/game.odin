package game

import "core:fmt"
import "core:image/png"
import "core:image"
import "base:runtime"
import os "core:os/os2"
import "core:time"
import "core:mem/virtual"
import "core:mem"
import "core:strings"
import "core:math/linalg"
import "core:thread"
import "core:slice"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"
import sa "core:container/small_array"
import ase "odin-aseprite"
import "odin-aseprite/utils"

@export
init_window :: proc() -> rawptr{
    rl.InitWindow(800, 600, "Hello Bingo")
    rl.SetWindowState({.WINDOW_RESIZABLE})
    return nil
}

@export
set_window_state :: proc(rawptr){}

ShaderType :: enum {
    Grid,
    Tilemap
}

FONT_SIZE :: 28

GameState :: struct {
    camera: rl.Camera2D,
    initialized: bool,

    tilemap: Tilemap,
    tilesets: sa.Small_Array(10, Tileset),

    tileset_index: int,
    brush_size: int,

    shaders: [ShaderType]ShaderInterface `fs:"-"`,
    default_font: rl.Font,
}
state: ^GameState


get_default_state :: proc() {

    state^ = {}

    state.camera = rl.Camera2D {
        zoom = 1,
        target = {}
    }

    // tilemap
    {
        state.tilemap.cel_size = 16

        // set tiles to image
        {
            image := rl.LoadImage("game/lake.jpg")
            defer rl.UnloadImage(image)
            colors := rl.LoadImageColors(image)
            defer rl.UnloadImageColors(colors)
            for i in 0..<TILEMAP_SIZE {
                for j in 0..<TILEMAP_SIZE {
                    if j >= int(image.width) do continue
                    if i >= int(image.height) do continue

                    image_index := i * int(image.width) + j
                    color := colors[image_index]

                    hsv := rl.ColorToHSV(color)
                    if hsv.z < .29  do continue

                    state.tilemap.tiles[j * TILEMAP_SIZE + i] = 1
                }
            }
        }
    }

    load_tilesets()

    state.initialized = true
}

load_tilesets :: proc(){

    sa.clear(&state.tilesets)

    doc: ase.Document
    defer ase.destroy_doc(&doc)

    umerr := ase.unmarshal_from_filename(&doc, "game/test.aseprite", context.temp_allocator)
    assert(umerr == nil, fmt.tprint(umerr))

    ts, tileset_err := utils.tileset_from_doc(&doc, context.temp_allocator)
    assert(tileset_err == nil)

    for tileset in ts {
        image := rl.Image {
            data = &tileset.tiles[0],
            width = i32(tileset.width),
            height = i32(tileset.height * tileset.num),
            mipmaps = 1,
            format = .UNCOMPRESSED_R8G8B8A8
        }
        sa.append(&state.tilesets, Tileset {
            texture = rl.LoadTextureFromImage(image),
            count = tileset.num
        })
    }
}

check_reload :: proc(files: []os.File_Info, start_time: ^time.Time) -> (os.File_Info, bool) {

    for file in files {
        if file.type == .Directory {
            continue
        }
        if file.modification_time._nsec > start_time._nsec {
            start_time^ = time.now()
            return file, true
        }
    }
    return {}, false
}

render_size :: proc() -> [2]f32 {
    return { f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight()) }
}

@export
run :: proc(error: bool, error_string: string, previous_state: []byte, game_allocator, state_allocator: runtime.Allocator) -> (current_state: []byte, reload: bool) {

    context.allocator = game_allocator

    state = new(GameState)

    defer {
        tilemap_destroy(&state.tilemap)
    }

    if len(previous_state) > 0 {
        deserialize(state, previous_state)
    }

    if !state.initialized {
        get_default_state()
    }

    state.shaders[.Grid] = load_shader("game/grid_vertex.glsl", "game/grid_fragment.glsl")
    state.shaders[.Tilemap] = load_shader("", "game/tilemap_fragment.glsl")

    state.default_font = rl.LoadFontEx("game/PCTL.ttf", FONT_SIZE, nil, 0)
    defer rl.UnloadFont(state.default_font)

    start_time := time.now()

    reload_timer := timer_start(1.5, false)

    start_file_checker()
    defer stop_file_checker()

    for !rl.WindowShouldClose(){
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        delta := rl.GetFrameTime()

        // reloading files
        {
            // files, err := os.read_all_directory_by_path(#directory, context.temp_allocator)
            files := read_all_directory_cached(#directory, context.temp_allocator)

            if file, updated := check_reload(files, &start_time); updated {
                if strings.has_suffix(file.name, ".odin") {
                    return serialize(state, state_allocator), true
                }
                if strings.has_suffix(file.name, ".aseprite") {
                    load_tilesets()
                }
                if strings.has_suffix(file.name, ".glsl"){
                    for &shader in state.shaders {
                        interface_check_reload(&shader)
                    }
                }
            }
        }



        if rl.IsKeyPressed(.TAB){
            get_default_state()
        }


        rl.BeginMode2D(state.camera)

        // editor(delta)

        rl.EndMode2D()


        load_gif(#load("Trailer3_720.gif"))


        timer_update(&reload_timer, delta)
        if reload_timer.running {
            rl.DrawTextEx(state.default_font, "reloaded", { render_size().x / 2, 0 }, FONT_SIZE, 1, rl.ColorBrightness(rl.GREEN, .2))
        }

        if error {
            rl.DrawRectangleV({}, render_size(), rl.ColorAlpha(rl.BLACK, .8))
            rl.DrawTextEx(state.default_font, fmt.ctprint(error_string), {}, FONT_SIZE, 1, rl.ColorBrightness(rl.RED, .2))
        }

        rl.DrawFPS(0, 0)

        rl.EndDrawing()
        free_all(context.temp_allocator)
        log_y_offset = 20
    }

    return
}

get_movement :: proc() -> [2]f32 {
    x := int(rl.IsKeyDown(.D)) - int(rl.IsKeyDown(.A))
    y := int(rl.IsKeyDown(.S)) - int(rl.IsKeyDown(.W))
    return linalg.normalize0([2]f32 { f32(x), f32(y) })
}


editor :: proc(delta: f32){

    camera := &state.camera

    // grid
    {
        grid_shader := &state.shaders[.Grid]
        grid_shader.uniforms["zoom"] = camera.zoom
        grid_shader.uniforms["grid_size"] = f32(state.tilemap.cel_size)
        if with_shader(grid_shader){
            start := rl.GetScreenToWorld2D({}, camera^)
            end := rl.GetScreenToWorld2D(render_size(), camera^)
            size := end - start
            rl.DrawRectangleV(start, size, rl.WHITE)
        }
    }

    // tilemap
    {
        brush: Brush

        {
            if rl.IsKeyPressed(.Q) do state.tileset_index -= 1
            if rl.IsKeyPressed(.E) do state.tileset_index += 1
            state.tileset_index %%= sa.len(state.tilesets)
        }
        tileset := sa.slice(&state.tilesets)[state.tileset_index]

        world_mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera^)

        mouse_coordinate := tilemap_get_coordinate(&state.tilemap, world_mouse)

        brush = Brush {
            coordinate = mouse_coordinate,
            radius = state.brush_size
        }

        if !rl.IsKeyDown(.LEFT_SHIFT) {
            if wheel_movement := rl.GetMouseWheelMove(); wheel_movement != 0 && rl.IsKeyDown(.LEFT_CONTROL) {
                state.brush_size += int(wheel_movement)
                state.brush_size = clamp(state.brush_size, 0, 100)
            }

            paint: i32 = -1
            if rl.IsMouseButtonDown(.LEFT) do paint = 1
            if rl.IsMouseButtonDown(.RIGHT) do paint = 0
            if paint != -1 {
                tilemap_paint(&state.tilemap, brush, paint)
            }
        }

        tilemap_draw(&state.tilemap, tileset, brush)
    }

    { // camera controls
        if rl.IsMouseButtonDown(.LEFT) && rl.IsKeyDown(.LEFT_SHIFT) {
            mouse_translation := rl.GetMouseDelta()
            camera.target -= mouse_translation / camera.zoom
        }

        ctrl_down := rl.IsKeyDown(.LEFT_CONTROL)
        if wheel_movement := rl.GetMouseWheelMove(); wheel_movement != 0 && !ctrl_down {
            zoom_delta := wheel_movement * .07 * camera.zoom
            camera.zoom = linalg.clamp(camera.zoom + zoom_delta, .001, 20)

            world_mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera^)

            camera.target = world_mouse
            camera.offset = rl.GetMousePosition()
        }
    }
}

log_y_offset: int
log :: proc(args: ..any, sep := " "){
    str := fmt.ctprint(..args, sep=sep)
    rl.DrawTextEx(state.default_font, str, { f32(20), f32(log_y_offset) }, FONT_SIZE, 1, rl.ColorBrightness(rl.BLUE, .8))
    log_y_offset += FONT_SIZE
}

log_color :: proc(color: rl.Color){
    border := rl.Rectangle { 20, f32(log_y_offset), FONT_SIZE, FONT_SIZE }
    pad: f32 = 1
    inner := rl.Rectangle { border.x + pad, border.y + pad, FONT_SIZE - pad * 2, FONT_SIZE - pad * 2 }
    rl.DrawRectangleRec(border, rl.WHITE)
    rl.DrawRectangleRec(inner, color)
    log_y_offset += FONT_SIZE + 10
}

log_image :: proc(data: []rl.Color, width, height: int, pixel_size: int) {
    start := [2]f32 { 20, f32(log_y_offset) }
    log_y_offset += pixel_size * int(height) + 10

    for i in 0..<height {
        for j in 0..<width {
            index := i * width + j
            color := data[index]
            pos := [2]f32 { f32(j * pixel_size), f32(i * pixel_size) }
            rl.DrawRectangleV(start + pos, f32(pixel_size), color)
        }
    }
}