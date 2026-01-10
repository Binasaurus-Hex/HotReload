package game

import "core:fmt"
import "core:os/os2"
import "core:time"
import "core:strings"
import "core:math/linalg"
import rl "vendor:raylib"
import sa "core:container/small_array"

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
    return serialize(&state, context.allocator)
}

@export
load :: proc(data: []u8) {
    deserialize(&state, data)
}

TileType :: enum {
    None, Yellow, White,
}

TILEMAP_SIZE :: 100
GRID_SIZE :: 10

GameState :: struct {
    camera: rl.Camera2D,
    initialized: bool,

    tiles: [TILEMAP_SIZE * TILEMAP_SIZE]TileType,
}

grid_shader: ShaderInterface
state: GameState

get_default_state :: proc() -> GameState {
    state: GameState

    state.camera = rl.Camera2D {
        zoom = 1,
        target = {}
    }

    state.initialized = true
    return state
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

default_font: rl.Font
FONT_SIZE :: 28

@export
run :: proc(error: bool, error_string: string) -> (reload: bool) {

    error_string := strings.clone(error_string, context.allocator)
    default_font = rl.LoadFontEx("game/PCTL.ttf", FONT_SIZE, nil, 0)

    start_time := time.now()

    reload_timer := timer_start(1, false)

    grid_shader = load_shader("game/grid_vertex.glsl", "game/grid_fragment.glsl")

    if !state.initialized {
        state = get_default_state()
    }

    for !rl.WindowShouldClose(){
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        delta := rl.GetFrameTime()

        interface_check_reload(&grid_shader)

        timer_update(&reload_timer, delta)

        if check_reload(start_time){
            return true
        }

        if rl.IsKeyPressed(.TAB){
            state = get_default_state()
        }


        rl.BeginMode2D(state.camera)

        editor(delta)

        rl.EndMode2D()

        test_serialization()

        if reload_timer.running {
            rl.DrawTextEx(default_font, "reloaded", { render_size().x / 2, 0 }, FONT_SIZE, 1, rl.ColorBrightness(rl.GREEN, .2))
        }

        if error {
            rl.DrawRectangleV({}, render_size(), rl.ColorAlpha(rl.BLACK, .8))
            rl.DrawTextEx(default_font, fmt.ctprint(error_string), {}, FONT_SIZE, 1, rl.ColorBrightness(rl.RED, .2))
        }

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
        world_mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera^)
        grid_location := linalg.floor(world_mouse / GRID_SIZE)
        start := grid_location *  GRID_SIZE
        defer {
            rl.DrawRectangleV(start, GRID_SIZE, rl.WHITE)
        }

        grid_location = linalg.clamp(grid_location, [2]f32{}, [2]f32{TILEMAP_SIZE, TILEMAP_SIZE})
        mouse_index := int(grid_location.x) * TILEMAP_SIZE + int(grid_location.y)
        mouse_index_valid := mouse_index >= 0 && mouse_index < len(state.tiles)
        if !rl.IsKeyDown(.LEFT_SHIFT) && mouse_index_valid {
            if rl.IsMouseButtonDown(.LEFT) do state.tiles[mouse_index] = .White
            else if rl.IsMouseButtonDown(.RIGHT) do state.tiles[mouse_index] = .None
        }

        for tile, i in state.tiles {
            row := i / TILEMAP_SIZE
            col := i % TILEMAP_SIZE
            start := [2]f32 { f32(row), f32(col) } * GRID_SIZE
            tile_colors := [TileType]rl.Color {
                .None = rl.BLANK,
                .White = rl.PURPLE,
                .Yellow = rl.YELLOW
            }
            rl.DrawRectangleV(start, GRID_SIZE, tile_colors[tile])
        }
    }

    { // camera controls
        if rl.IsMouseButtonDown(.LEFT) && rl.IsKeyDown(.LEFT_SHIFT) {
            mouse_translation := rl.GetMouseDelta()
            camera.target -= mouse_translation / camera.zoom
        }

        if wheel_movement := rl.GetMouseWheelMove(); wheel_movement != 0 {
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

import "core:encoding/cbor"

test_serialization :: proc(){

    Blob :: struct {
        blobness: f32,
        succ: f32,
    }

    Height :: enum {
        LOW, MEDIUM, HIGH
    }

    Feature :: enum {
        Burnable,
        Eatable,
        Breakable,
        Cargo,
    }

    Circle :: struct { radius: f32, centre: [2]f32 }
    Rectangle :: struct { origin: [2]f32, size: [2]f32 }

    Shape :: union {
        Circle, Rectangle
    }

    Thing :: struct {
        position: [2]f32,
    }

    BlobCount :: 2000

    TestStruct1 :: struct {
        position, velocity: [2]f32,
        data: [BlobCount]Blob,
        altitude: [Height]f32,
        features: bit_set[Feature],
        shape: Shape,
        things: sa.Small_Array(10, Thing),
        timer: Timer,
    }

    test_struct := TestStruct1 {
        position = { 1, 2 },
        velocity = {3, 4 },
        altitude = {
            .LOW = 1, .MEDIUM = 2.2, .HIGH = 4.20
        },
        shape = Rectangle { {2, 4} , { 4, 4 }},
        features = { .Cargo, .Burnable, .Breakable },
        timer = timer_start(2, true)
    }
    for i in 0..<10 {
        sa.append(&test_struct.things, Thing {{f32(i), f32(i + 1)}})
    }

    NewFeature :: enum {
        Burnable,
        Cargo,
        Breakable,
        Eatable,
    }

    NewThing :: struct {
        velocity: [2]f32,
        position: [2]f32,
    }

    Triangle :: struct {
        points: [3][2]f32
    }

    NewShape :: union {
        Circle,
        Triangle,
        Rectangle,
    }

    NewHeight :: enum {
        LOW,
        MEDIUM,
        HIGH,
    }

    TestStruct2 :: struct {
        position, velocity: [2]f32,
        data: [BlobCount]Blob,
        altitude: [NewHeight]f32,
        features: bit_set[NewFeature],
        // health: f32,
        shape: NewShape,
        things: sa.Small_Array(10, NewThing),
        timer: Timer,
    }

    TEST_ITERATIONS :: 10
    // cbor
    {
        start := time.now()

        for i in 0..<TEST_ITERATIONS {
            data, err := cbor.marshal(test_struct, cbor.ENCODE_FULLY_DETERMINISTIC)
            assert(err == nil)

            replicated := TestStruct2 {}
            cbor.unmarshal(data, &replicated, allocator = context.temp_allocator)
        }

        duration := time.duration_seconds(time.since(start))
        log("cbor:    ", duration, "s")
    }

    // buffer
    {
        start := time.now()

        for i in 0..<TEST_ITERATIONS {
            data := serialize(&test_struct)
            replicated := TestStruct2 {}
            deserialize(&replicated, data)
        }

        duration := time.duration_seconds(time.since(start))
        log("buffer: ", duration, "s")
    }
}
