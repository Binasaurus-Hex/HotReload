package game

import "core:fmt"
import "core:os/os2"
import "core:time"
import "core:strings"
import "core:math/linalg"
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

@export
save :: proc() -> []u8 {
    return serialize(state, context.allocator)
}

@export
load :: proc(data: []u8) {
    if state == nil {
        state = new(GameState)
    }
    deserialize(state, data)
}

TILEMAP_SIZE :: 16 * 100
GRID_SIZE :: 16

GameState :: struct {
    camera: rl.Camera2D,
    initialized: bool,
    tileset_index: int,
    tiles: [TILEMAP_SIZE * TILEMAP_SIZE]i32,
    tile_buffer: u32
}

grid_shader: ShaderInterface
tilemap_shader: ShaderInterface
state: ^GameState
default_font: rl.Font

Tileset :: struct {
    texture: rl.Texture,
    count: int
}
tilesets: sa.Small_Array(10, Tileset)

get_default_state :: proc() -> ^GameState {
    s := new(GameState)

    s.camera = rl.Camera2D {
        zoom = 1,
        target = {}
    }

    // set tiles to image
    {
        image := rl.LoadImage("game/monke.jpg")
        colors := rl.LoadImageColors(image)
        for i in 0..<TILEMAP_SIZE {
            for j in 0..<TILEMAP_SIZE {
                if j >= int(image.width) do continue
                if i >= int(image.height) do continue

                image_index := i * int(image.width) + j
                color := colors[image_index]

                hsv := rl.ColorToHSV(color)
                if hsv.z < .4  do continue

                s.tiles[j * TILEMAP_SIZE + i] = 1
                // fmt.println(hsv)
            }
        }
    }

    s.initialized = true
    s.tile_buffer = rlgl.LoadShaderBuffer(len(s.tiles) * size_of(i32), &s.tiles, rlgl.DYNAMIC_COPY)
    return s
}

check_reload :: proc(start_time: time.Time, path := #directory) -> bool {

    files, read_err := os2.read_all_directory_by_path(path, context.temp_allocator)
    assert(read_err == nil, fmt.tprint(read_err))
    for file in files {
        if file.type == .Directory {
            if check_reload(start_time, file.fullpath) do return true
        }
        if !strings.has_suffix(file.name, ".odin") do continue
        if file.modification_time._nsec > start_time._nsec do return true
    }
    return false
}

render_size :: proc() -> [2]f32 {
    return { f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight()) }
}

FONT_SIZE :: 28

@export
run :: proc(error: bool, error_string: string) -> (reload: bool) {


    if state == nil || !state.initialized {
        state = get_default_state()
    }


    {
        doc: ase.Document
        defer ase.destroy_doc(&doc)

        umerr := ase.unmarshal_from_filename(&doc, "game/test.aseprite", context.allocator)
        assert(umerr == nil)

        ts, tileset_err := utils.tileset_from_doc(&doc)
        assert(tileset_err == nil)

        for tileset in ts {
            image := rl.Image {
                data = &tileset.tiles[0],
                width = i32(tileset.width),
                height = i32(tileset.height * tileset.num),
                mipmaps = 1,
                format = .UNCOMPRESSED_R8G8B8A8
            }
            sa.append(&tilesets, Tileset {
                texture = rl.LoadTextureFromImage(image),
                count = tileset.num
            })
        }
    }

    error_string := strings.clone(error_string, context.allocator)
    default_font = rl.LoadFontEx("game/PCTL.ttf", FONT_SIZE, nil, 0)

    start_time := time.now()

    reload_timer := timer_start(1, false)

    grid_shader = load_shader("game/grid_vertex.glsl", "game/grid_fragment.glsl")

    tilemap_shader = load_shader("game/grid_vertex.glsl", "game/tilemap_fragment.glsl")


    for !rl.WindowShouldClose(){
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        delta := rl.GetFrameTime()

        interface_check_reload(&grid_shader)
        interface_check_reload(&tilemap_shader)

        timer_update(&reload_timer, delta)

        if check_reload(start_time){
            return true
        }

        if rl.IsKeyPressed(.TAB){
            free(state)
            state = get_default_state()
        }


        rl.BeginMode2D(state.camera)

        editor(delta)

        rl.EndMode2D()

        // test_serialization()

        if reload_timer.running {
            rl.DrawTextEx(default_font, "reloaded", { render_size().x / 2, 0 }, FONT_SIZE, 1, rl.ColorBrightness(rl.GREEN, .2))
        }

        if error {
            rl.DrawRectangleV({}, render_size(), rl.ColorAlpha(rl.BLACK, .8))
            rl.DrawTextEx(default_font, fmt.ctprint(error_string), {}, FONT_SIZE, 1, rl.ColorBrightness(rl.RED, .2))
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
        grid_shader.uniforms["zoom"] = camera.zoom
        grid_shader.uniforms["grid_size"] = f32(GRID_SIZE)
        if with_shader(&grid_shader){
            start := rl.GetScreenToWorld2D({}, camera^)
            end := rl.GetScreenToWorld2D(render_size(), camera^)
            size := end - start
            rl.DrawRectangleV(start, size, rl.WHITE)
        }
    }

    // tilemap
    {
        {
            if rl.IsKeyPressed(.Q) do state.tileset_index -= 1
            if rl.IsKeyPressed(.E) do state.tileset_index += 1
            state.tileset_index %%= sa.len(tilesets)
        }
        tileset := sa.slice(&tilesets)[state.tileset_index]

        world_mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera^)
        grid_location := linalg.floor(world_mouse / GRID_SIZE)
        start := grid_location *  GRID_SIZE

        coordinate := linalg.array_cast(grid_location, int)
        coordinate = linalg.clamp(coordinate, 0, TILEMAP_SIZE - 1)
        mouse_cel := coordinate.x * TILEMAP_SIZE + coordinate.y

        paint_cels :: proc(cels: []i32, coordinate: [2]int, size: int, value: i32) {
            if size == 0 {
                cel := coordinate.x * TILEMAP_SIZE + coordinate.y
                try_paint(cels, cel, value)
                return
            }
            start: int = -size
            iterations: int = size * 2 + 1
            for i in 0..<iterations{
                for j in 0..<iterations{
                    coord := [2]int { i, j } + start
                    float_coord := linalg.array_cast(coord, f32)
                    if linalg.length(float_coord) > f32(size) do continue

                    coord += coordinate
                    cel := coord.x * TILEMAP_SIZE + coord.y
                    try_paint(cels, cel, value)
                }
            }
        }


        try_paint :: proc(tiles: []i32, cel: int, value: i32){
            if cel < 0 || cel >= len(tiles) do return
            tiles[cel] = value
        }

        @static brush_size: int = 1

        if !rl.IsKeyDown(.LEFT_SHIFT) {
            if wheel_movement := rl.GetMouseWheelMove(); wheel_movement != 0 && rl.IsKeyDown(.LEFT_CONTROL) {
                brush_size += int(wheel_movement)
                brush_size = clamp(brush_size, 0, 100)
            }

            paint: int = -1
            if rl.IsMouseButtonDown(.LEFT) do paint = 1
            if rl.IsMouseButtonDown(.RIGHT) do paint = 0
            if paint != -1 {

                paint_cels(state.tiles[:], linalg.array_cast(grid_location, int), brush_size, i32(paint))
            }
        }

        {


            {
                tile_definitions := [6][4]i32 {
                    {0, 0, 0, 0},

                    {0, 0, 0, 1},

                    {0, 0, 1, 1},

                    {0, 1, 0, 1},

                    {1, 0, 1, 1},

                    {1, 1, 1, 1},
                }
                definitions_slice := slice.reinterpret([]i32, tile_definitions[:])
                tilemap_shader.uniforms["tile_definitions"] = definitions_slice
            }

            tilemap_shader.uniforms["brush_radius"] = i32(brush_size)
            tilemap_shader.uniforms["tilemap_size"] = i32(TILEMAP_SIZE)
            tilemap_shader.uniforms["cel_size"] = i32(GRID_SIZE)
            tilemap_shader.uniforms["tileset_count"] = i32(tileset.count)
            tilemap_shader.uniforms["mouse_coord"] = [2]i32 { i32(mouse_cel / TILEMAP_SIZE), i32(mouse_cel % TILEMAP_SIZE) }
            rlgl.UpdateShaderBuffer(state.tile_buffer, &state.tiles[0], u32(size_of(i32) * len(state.tiles)), 0)

            quad_size :[2]f32 = TILEMAP_SIZE * GRID_SIZE
            dest := rl.Rectangle {0, 0, f32(quad_size.x), f32(quad_size.y)}

            if with_shader(&tilemap_shader){
                rlgl.BindShaderBuffer(state.tile_buffer, 0)
                draw_textured_rect(tileset.texture, dest)
            }
        }
    }

    { // camera controls
        if rl.IsMouseButtonDown(.LEFT) && rl.IsKeyDown(.LEFT_SHIFT) {
            mouse_translation := rl.GetMouseDelta()
            camera.target -= mouse_translation / camera.zoom
        }

        ctrl_down := rl.IsKeyDown(.LEFT_CONTROL)
        if wheel_movement := rl.GetMouseWheelMove(); wheel_movement != 0 && !ctrl_down {
            zoom_delta := wheel_movement * .07 * camera.zoom
            camera.zoom = linalg.clamp(camera.zoom + zoom_delta, .01, 20)

            world_mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera^)

            camera.target = world_mouse
            camera.offset = rl.GetMousePosition()
        }
    }
}

log_y_offset: int
log :: proc(args: ..any, sep := " "){
    str := fmt.ctprint(..args, sep=sep)
    rl.DrawTextEx(default_font, str, { f32(20), f32(log_y_offset) }, FONT_SIZE, 1, rl.ColorBrightness(rl.BLUE, .8))
    log_y_offset += FONT_SIZE
}