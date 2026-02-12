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
import "core:path/filepath"
import "core:path/slashpath"

RELEASE :: #config(RELEASE, false)

TextureType :: enum {

    Player,

    // crates
    Crate_Astantine,
    Crate_Inverse_Matter,
    Crate_Nanobots,
    Crate_Scrap,
    Crate_Hydrogen,
    Crate_Beef,
    Crate_Medical_Supplies,
    Crate_Argon,
    Crate_Titanium
}

when RELEASE {
    main :: proc(){
        rl.InitWindow(800, 600, "game")
        rl.SetWindowState({.WINDOW_RESIZABLE})
        run(false, "", {}, context.allocator, context.allocator)
    }
}

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

TagType :: enum {
    Intro,
    Helmet_On,
    TractorBeamSwitchIn,
    PistolShoot,
    PistolReload
}
tag_names :: [TagType]string {
    .Intro =                "intro",
    .Helmet_On =            "helmet_on",
    .TractorBeamSwitchIn =  "tractor_beam_switch_in",
    .PistolShoot =          "pistol_shoot",
    .PistolReload =         "pistol_reload"
}

Tag :: struct {
    from, to: int,
    type: TagType
}

GameState :: struct {
    camera: rl.Camera2D,
    initialized: bool,

    tilemap: Tilemap,
    tilesets: [TilesetType]Tileset,

    tileset_index: int,
    brush_size: int,

    shaders: [ShaderType]ShaderInterface `fs:"-"`,
    default_font: rl.Font,

    textures: [TextureType]rl.Texture,
    tags: [TextureType][TagType]Tag,
    frames: [TextureType]int
}
state: ^GameState

texture_load_paths :: [TextureType][2]string {
    .Crate_Argon =                  { "crate.aseprite", "argon" },
    .Crate_Astantine =              { "crate.aseprite", "astantine" },
    .Crate_Titanium =               { "crate.aseprite", "titanium" },
    .Crate_Hydrogen =               { "crate.aseprite", "hydrogen" },
    .Crate_Beef =                   { "crate.aseprite", "beef" },
    .Crate_Inverse_Matter =         { "crate.aseprite", "InverseMatter" },
    .Crate_Nanobots =               { "crate.aseprite", "nanobots" },
    .Crate_Scrap =                  { "crate.aseprite", "scrap" },
    .Crate_Medical_Supplies =       { "crate.aseprite", "medical_supplies" },
    .Player =                       { "player.aseprite", "-" }
}

TilesetType :: enum {
    Debug,
    Grass,
    Clay,
    Block
}

tileset_load_paths :: [TilesetType][2]string {
    .Debug = { "test.aseprite", "debug" },
    .Grass = { "test.aseprite", "grass" },
    .Clay =  { "test.aseprite", "clay" },
    .Block = { "test.aseprite", "block" }
}

get_default_state :: proc() {

    state^ = {}

    state.camera = rl.Camera2D {
        zoom = 1,
        target = {}
    }

    // tilemap
    if true {
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

    load_aseprite("game/test.aseprite")
    load_aseprite("game/player.aseprite")
    load_aseprite("game/crate.aseprite")

    state.initialized = true
}

load_aseprite :: proc(filename: string){

    _, name := filepath.split(filename)

    doc: ase.Document
    defer ase.destroy_doc(&doc)

    context.allocator = context.temp_allocator

    data, read_err := os.read_entire_file_from_path(filename, context.allocator)
    assert(read_err == nil, fmt.tprint(read_err))

    unmarshal_err := ase.unmarshal_from_slice(&doc, data)
    assert(unmarshal_err == nil, fmt.tprint(unmarshal_err))

    info: utils.Info
    info_err := utils.get_info(&doc, &info)
    assert(info_err == nil)

    get_texture_type :: proc(filename, layer_name: string) -> (type: TextureType, found: bool) {
        for path, t in texture_load_paths {
            if path.x != filename do continue
            if path.y != layer_name do continue
            return t, true
        }
        return
    }

    if len(info.frames) <= 1 {
        cels := info.frames[0].cels

        for cel in cels {
            layer_name := info.layers[cel.layer].name

            texture_type := get_texture_type(name, layer_name) or_continue

            if len(cel.raw) == 0 do continue
            image := rl.Image {
                data = &cel.raw[0],
                width = i32(cel.width),
                height = i32(cel.height),
                format = .UNCOMPRESSED_R8G8B8A8,
                mipmaps = 1
            }
            texture := rl.LoadTextureFromImage(image)

            state.textures[texture_type] = texture
        }
    }
    else if texture_type, found := get_texture_type(name, "-"); found {

        sprite_info := utils.Sprite_Info {
            size = { info.md.width, info.md.height },
            count = len(info.frames)
        }
        sheet, sheet_err := utils.create_sprite_sheet_from_info(info, sprite_info)

        sheet_image := rl.Image {
            data = &sheet.data[0],
            width = i32(sheet.width),
            height = i32(sheet.height),
            format = .UNCOMPRESSED_R8G8B8A8,
            mipmaps = 1
        }

        sheet_texture := rl.LoadTextureFromImage(sheet_image)

        state.textures[texture_type] = sheet_texture
        for &tag in info.tags {

            get_tag :: proc(name: string) -> (type: TagType, ok: bool) {
                for tag_name, tag_type in tag_names {
                    if tag_name != name do continue
                    return tag_type, true
                }
                return {}, false
            }
            tag_type: TagType = get_tag(tag.name) or_continue
            state.tags[texture_type][tag_type] = Tag {
                from = tag.from,
                to = tag.to,
                type = tag_type
            }
        }
        state.frames[texture_type] = len(info.frames)
    }

    if len(info.tilesets) > 0 {
        for tileset in info.tilesets {

            get_type :: proc(file_name, tileset_name: string) -> (type: TilesetType, found: bool) {
                for path, t in tileset_load_paths {
                    if path.x != file_name do continue
                    if path.y != tileset_name do continue
                    return t, true
                }
                return
            }

            tileset_type := get_type(name, tileset.name) or_continue

            image := rl.Image {
                data = &tileset.tiles[0],
                width = i32(tileset.width),
                height = i32(tileset.height * tileset.num),
                mipmaps = 1,
                format = .UNCOMPRESSED_R8G8B8A8
            }
            texture := rl.LoadTextureFromImage(image)
            state.tilesets[tileset_type] = Tileset {
                texture = texture,
                count = tileset.num
            }
        }
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
            files := read_all_directory_cached(#directory, context.temp_allocator)

            if file, updated := check_reload(files, &start_time); updated {
                if strings.has_suffix(file.name, ".odin") {
                    return serialize(state, state_allocator), true
                }
                if strings.has_suffix(file.name, ".aseprite") {
                    file_wait(file.fullpath)
                    load_aseprite(file.fullpath)
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

        editor(delta)

        rl.EndMode2D()

        for texture, type in state.textures {
            scale :f32 = 3
            frames: int = state.frames[type]
            if frames > 0 {
                current_animation := TagType.Intro
                @static animation_frame: int
                @static timer: Timer
                if !timer.running do timer = timer_start(.1, true)

                tag := state.tags[type][current_animation]
                range := tag.to - tag.from
                if range > 0 {
                    if timer_update(&timer, delta){
                        animation_frame += 1
                        animation_frame %= (tag.to - tag.from)
                    }
                    log_texture_frame(texture, frames, tag.from + animation_frame, scale)
                }
            }
            else {
                log_texture(texture, scale)
            }
        }

        timer_update(&reload_timer, delta)
        if reload_timer.running {
            rl.DrawTextEx(state.default_font, "reloaded", { render_size().x / 2, 0 }, FONT_SIZE, 1, rl.ColorBrightness(rl.GREEN, .2))
        }

        if error {
            rl.DrawRectangleV({}, render_size(), rl.ColorAlpha(rl.BLACK, .8))
            screen := fullscreen_rect()
            error_color := rl.ColorBrightness(rl.RED, .2)
            ui_draw_textblock(error_string, screen, error_color, state.default_font)
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
            state.tileset_index %%= len(state.tilesets)
        }
        tileset := state.tilesets[TilesetType(state.tileset_index)]

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

LOG_PADDING :: 10
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

log_texture :: proc(texture: rl.Texture, scale: f32 = 1){
    start := [2]f32 { LOG_PADDING, f32(log_y_offset) }
    log_y_offset += int(f32(texture.height) * scale) + LOG_PADDING
    rl.DrawTextureEx(texture, start, 0, scale, rl.WHITE)
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

log_texture_frame :: proc(texture: rl.Texture, frames, frame: int, scale: f32 = 1){
    start := [2]f32 { LOG_PADDING, f32(log_y_offset) }
    log_y_offset += int(f32(texture.height) * scale) + LOG_PADDING
    draw_frame(texture, start, frames, frame, scale)
}

draw_frame :: proc(texture: rl.Texture, position: [2]f32, frames, frame: int, scale: f32 = 1){
    cel_width := f32(texture.width) / f32(frames)
    cel_height := f32(texture.height)
    source := rl.Rectangle {
        cel_width * f32(frame),
        0,
        cel_width,
        cel_height
    }

    destination := rl.Rectangle {
        position.x,
        position.y,
        cel_width * scale,
        cel_height * scale
    }

    rl.DrawTexturePro(texture, source, destination, {}, 0, rl.WHITE)
}