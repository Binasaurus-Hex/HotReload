package game

import rl "vendor:raylib"
import "core:mem"
import "core:odin/tokenizer"
import "core:fmt"
import "core:math/linalg"

Stage :: enum {
    Title,
    End,
}

SlideShow :: struct {
    stage:              int,
    previous_stage:     int,
    stage_timer:    Timer,
    enter: bool,
    delta: f32,
    modules: [dynamic]Module,
}

ModuleFeature :: enum {
    File, NoHeader, Block
}
Module :: struct {
    features:   bit_set[ModuleFeature],
    name:       string,
    code:       string,
    steps:      []string,
    active_step: int,
    active:     bool,
    visible:    bool,
    rect:       Rect,
    default:    Rect,
    reset:      bool,
}

TEXT_COLOR :: 0xBFC9DBFF
BACKGROUND_2 :: 0x10191FFF
BACKGROUND_3 :: 0x18262FFF
BACKGROUND_4 :: 0x1A2831FF
BACKGROUND_5 :: 0x21333FFF
UI_DEFAULT :: 0xBFC9DBFF
CODE_HIGHLIGHT :: 0x1C4449FF
CODE_COMMENT :: 0x87919DFF

slide_wait :: proc(slideshow: ^SlideShow, duration: f32){
    timer_try_start(&slideshow.stage_timer, duration)
    if timer_update(&slideshow.stage_timer, slideshow.delta){
        slideshow.stage += 1
    }
}

slide_text :: proc(
    slideshow: ^SlideShow,
    text: string,
    rect: Rect,
    animation_speed: f32 = 20,
    reset := false,
    id := Id(0),
    color := rl.WHITE,
    scale: f32 = 1,
    flags := bit_set[TextFlag]{.Centre},
    from: Rect = {},
    animate := true
) {
    delta := slideshow.delta
    reset := slideshow.enter && reset
    id := get_id(text) if id == {} else id
    rect := interpolate_rect(rect, id, delta, reset = reset, default = from)

    text := text
    display_length: int = len(text)

    if animate {
        animated := animate_string(text, animation_speed * 2, delta, reset = reset, id = id)
        if .Wrap in flags {
            display_length = len(animated)
        }
        else {
            text = animated
        }
    }
    color := interpolate_color_hsva(color, id, delta, reset)
    scale := interpolate_scale(scale, id, delta, reset)
    draw_text(.UI, text, rect, color, {}, scale, flags, display_length)
}

slideshow :: proc(slideshow: ^SlideShow, delta: f32){

    slideshow.delta = delta
    previous_stage := slideshow.stage
    defer slideshow.previous_stage = previous_stage

    { // controls
        offset: int
        if rl.IsKeyPressed(.LEFT) do offset -= 1
        if rl.IsKeyPressed(.RIGHT) do offset += 1
        slideshow.stage = clamp(slideshow.stage + offset, 0, 100000)

        if rl.IsKeyPressed(.SPACE) do slideshow.stage = 0
    }

    content := pad_rect(fullscreen_rect(), 50)

    slideshow.enter = slideshow.stage != slideshow.previous_stage
    if slideshow.enter do slideshow.stage_timer = {}

    // debug
    {
        top := eat_top_rect_ref(&content, 50, 10)

        timer := eat_left_rect_ref(&top, 200, 10)
        draw_text(.UI, fmt.tprintf("timer = %.2f", slideshow.stage_timer.elapsed), timer, rl.RED)

        stage := eat_left_rect_ref(&top, 200, 10)
        draw_text(.UI, fmt.tprintf("stage = %d", slideshow.stage), stage, rl.RED)
    }

    TITLE := get_id("title")
    DESC := get_id("description")

    WHITE :: rl.Color { 200, 200, 200, 255 }
    LIGHT_GREY :: rl.Color { 120, 150, 200, 255 }
    GREEN :: rl.Color { 100, 220, 120, 255 }
    BACKGROUND := rl.GetColor(0x15212AFF)

    draw_rect(.UI, fullscreen_rect(), BACKGROUND, BACKGROUND)

    stage_switch: switch slideshow.stage {
    case 0:
        slide_text(slideshow, "Hot Reloading", content, id = TITLE, scale = 3)
    case 1:
        title := eat_top_rect_ref(&content, 200, 10)
        slide_text(slideshow, "What is it?", title, id = TITLE, color = LIGHT_GREY, scale = 1.5)
        desc := "The ability to modify an asset live\nwhile the game or editor is running"
        desc_rect := pad_rect(content, 50)
        slide_text(slideshow, desc, desc_rect, from = desc_rect + { -1000, 0, 0, 0}, id = DESC, flags = { .Wrap }, color = rl.WHITE, scale = 2, reset = true)
    case 2..=5:
        slide_index := slideshow.stage - 2
        title := pad_rect(eat_top_rect_ref(&content, 200, 10), 100)
        desc := "The ability to modify an asset live\nwhile the game or editor is running"
        slide_text(slideshow, desc, title, id = DESC, flags = { .Wrap }, color = LIGHT_GREY, scale = 1.5)

        asset_types := []string { "code", "textures", "shaders" }
        colors := []rl.Color { GREEN, rl.ORANGE, rl.BLUE }
        for v, i in asset_types {
            if slide_index == i do break stage_switch
            current := slide_index - 1 == i
            r := eat_top_rect_ref(&content, 100, 10)
            slide_text(slideshow, v, r, color = colors[i], reset = current, scale = 1.5)
        }
    case 6..=13:

        title_r := eat_top_rect_ref(&content, 100, 10)
        slide_text(slideshow, "code", title_r, scale = 2)

        modules := make([dynamic]Module, context.temp_allocator)
        module_append :: proc(modules: ^[dynamic]Module, module: Module) -> int {
            index := len(modules)
            append(modules, module)
            return index
        }

        game_file := module_append(&modules, Module {
            name = "game.odin",
            features = {.File},
            code = string(#load("game.odin")),
            visible = true
        })

        exe := module_append(&modules, Module {
            name = "exe",
            steps = { "build", "run" },
            visible = true
        })

        dll := module_append(&modules, Module {
            name = "dll",
            steps = { "check reload", "update", "render" },
            visible = false
        })

        file_copy := module_append(&modules, Module {})
        gamestate := module_append(&modules, Module {name = "state", features = {.Block}})

        middle := pad_rect(centre_rect(content), -{300, 200 })
        top_row := eat_top_rect_ref(&middle, 100, 200)
        bottom_row := eat_top_rect_ref(&middle, 200, 200)

        // start places
        modules[game_file].rect = pad_rect(centre_rect(top_row), -{80, 100 })
        left, right := eat_left_rect(bottom_row, 200, 200)
        modules[exe].rect = left
        modules[dll].rect = right

        switch slideshow.stage {
        case 6:
            // default
        case 7:
            modules[exe].active = true
            modules[exe].active_step = 0
        case 8:
            modules[exe].active = true
            modules[exe].active_step = 0

            file := modules[game_file]
            file.name = "copy"
            file.active = true
            file.default = file.rect
            file.rect.x -= 200
            file.reset = slideshow.enter
            modules[file_copy] = file
        case 9:
            modules[exe].active = true
            modules[exe].active_step = 0

            file := modules[game_file]
            file.name = "copy"
            file.rect = modules[exe].rect
            file.rect.zw = 50
            file.rect.y += 20
            file.features += {.NoHeader }
            modules[file_copy] = file
        case 10:
            modules[dll].visible = true
            modules[dll].reset = slideshow.enter
            dll_spawn := modules[exe].rect
            dll_spawn.zw = 10
            dll_spawn.x += 200
            dll_spawn.y += 10
            modules[dll].default = dll_spawn
            modules[exe].active = true
            modules[exe].active_step = -1

            // gamestate
            modules[gamestate].rect = pad_rect(centre_rect(modules[exe].rect), -50)
            modules[gamestate].rect.xy += { 0, 100 }
            modules[gamestate].visible = true
        case 11:
            modules[exe].active = true
            modules[exe].active_step = 1
            modules[dll].visible = true
            modules[dll].active = true
            modules[dll].active_step = int(state.elapsed) % len(modules[dll].steps)

            modify_label_color := rl.ColorBrightness(rl.GetColor(CODE_COMMENT), -.5)
            modified: bool
            if modules[dll].active_step == 0 {
                modify_label_color = rl.GetColor(TEXT_COLOR)
                modules[game_file].active = true
            }
            modify_label :=  modules[game_file].rect
            modify_label.xy += { 170, -120 }

            slide_text(slideshow, "modified? No", modify_label, id = get_id("modified"), color = modify_label_color, scale = .8)

            exe_actual := state.ui_state.rects[get_id(uintptr(&modules[exe]))]
            dll_actual := state.ui_state.rects[get_id(uintptr(&modules[dll]))]
            line := [2][2]f32 { exe_actual.xy + { 190, 90 }, dll_actual.xy + { 0, 10 }}

            modules[gamestate].visible = true
            modules[gamestate].rect = { line.x.x, line.x.y, 10, 10}

            length := interpolate_scale(1, get_id("run line"), delta, reset = slideshow.enter)
            draw_line(.UI, scale_line(line, length), rl.GetColor(CODE_HIGHLIGHT), 5)
        case 12:

            modules[exe].active = true
            modules[exe].active_step = 1
            modules[dll].visible = true
            modules[dll].active = true
            modules[dll].active_step = 0



            modify_label_color := rl.ColorBrightness(rl.GetColor(CODE_COMMENT), -.5)
            modified: bool
            if modules[dll].active_step == 0 {
                modify_label_color = rl.GetColor(TEXT_COLOR)
                modules[game_file].active = true
            }
            modify_label :=  modules[game_file].rect
            modify_label.xy += { 170, -120 }
            slide_text(slideshow, "modified? Yes", modify_label, id = get_id("modified"), color = modify_label_color, scale = .9)

            exe_actual := state.ui_state.rects[get_id(uintptr(&modules[exe]))]
            dll_actual := state.ui_state.rects[get_id(uintptr(&modules[dll]))]
            line := [2][2]f32 { exe_actual.xy + { 180, 100 }, dll_actual.xy + { 0, 10 }}

            modules[gamestate].visible = true
            modules[gamestate].rect = { line.y.x, line.y.y, 10, 10}

            draw_line(.UI, line, rl.GetColor(CODE_HIGHLIGHT), 5)

        case 13:
            slideshow.stage = 8
        }

        for &module in modules {
            slide_draw_module(slideshow, module.rect, &module, slideshow.enter && slideshow.stage == 6)
        }

    }
}

slide_code :: proc(slideshow: ^SlideShow, code: string, rect: Rect, scale: f32 = 1){
    original_rect := rect
    rect := rect
    size := f32(state.default_font.baseSize) / 2 * scale
    list := eat_top_rect_ref(&rect, size, 0)
    t: tokenizer.Tokenizer
    tokenizer.init(&t, code, "")
    TAB_SIZE :f32 = 10 * scale

    tokens := make([dynamic]tokenizer.Token, context.temp_allocator)
    for {
        token := tokenizer.scan(&t)
        append(&tokens, token)
        if token.kind == .EOF do break
    }

    code_comment := rl.GetColor(CODE_COMMENT)
    keyword := rl.GetColor(0xE67D74FF)
    proc_call := rl.GetColor(0xD0C5A9FF)
    code_string := rl.GetColor(0xD4BC7DFF)
    code_value := rl.GetColor(0xD699B5FF)
    code_operator := rl.GetColor(0xBFC9DBFF)
    code_type := rl.GetColor(0x82AAA3FF)

    line: int = 0
    for &token, i in tokens {
        if token.kind == .EOF do break
        next := tokens[i + 1]

        size := measure_text(token.text, state.default_font) * scale

        if token.pos.line != line {
            line = token.pos.line
            list = eat_top_rect_ref(&rect, size.y, 0)
            eat_left_rect_ref(&list, f32(token.pos.column) * TAB_SIZE, 0)
        }

        color := rl.WHITE
        switch {
        case token.kind == .Comment:
            color = code_comment
        case tokenizer.is_keyword(token.kind):
            color = keyword
        case tokenizer.is_literal(token.kind):

            #partial switch token.kind {
            case .Ident:
                if next.text == "(" || next.text == ":" {
                    color = proc_call
                }
                else {
                    color = code_operator
                }
            case .Integer, .Float, .Imag, .Rune:
                color = code_value
            case .String:
                color = code_string
            }
            switch token.text {
            case "bool", "byte":
                color = code_type
            case "true", "false":
                color = code_value
            }
        case tokenizer.is_operator(token.kind):
            color = code_operator
        }
        r := eat_left_rect_ref(&list, size.x, 10 * scale)
        if rect_overlaps(state.ui_state.clip_rect, r){
            draw_text(.UI, token.text, r, color = color, scale = scale, flags = {.NoClone })
        }
    }
}

slide_draw_module :: proc(slideshow: ^SlideShow, rect: Rect, module: ^Module, reset: bool){
    reset := reset || module.reset
    if !module.visible do return
    shadow_begin(.UI, 10)
    id := get_id(uintptr(module))
    rect := interpolate_rect(rect, id, state.delta, reset, default = module.default, speed = 5)
    code_comment := rl.GetColor(CODE_COMMENT)
    background := rl.GetColor(BACKGROUND_5)
    raised := rl.ColorBrightness(background, -.1)
    background_2 := rl.GetColor(0x15212AFF)
    text_color := rl.GetColor(TEXT_COLOR)
    code_highlight := rl.GetColor(CODE_HIGHLIGHT)
    draw_rect(.UI, rect, background, background)

    if module.active {
        outline := pad_rect(rect, 4)
        draw_rect(.UI, outline, code_highlight, code_highlight)
        light := pad_rect(outline, 5)
        draw_rect(.UI, light, code_comment, code_comment)
        draw_rect(.UI, pad_rect(light, 1), background, background)
    }

    if .Block in module.features {
        draw_text(.UI, module.name, rect, code_comment)
        return
    }
    text_scale :f32 = 1
    text_size := measure_text(module.name, state.default_font) * text_scale + { 30, 10 }
    text_size.x = max(text_size.x, 100)
    label := rect
    label.zw = text_size
    label.y -= label.w

    if .NoHeader not_in module.features {
        draw_rect(.UI, label, background, background)
        draw_text(.UI, module.name, label, text_color, scale = text_scale)
    }

    inner := pad_rect(rect, 10)

    if .File in module.features {
        state.ui_state.clip_rect = inner

        clip_rect_begin(.UI, inner)
        offset := linalg.mod(state.elapsed * 50, 8000)
        slide_code(slideshow, module.code, inner - { 0, offset, 0, 0 }, scale = .6)
        clip_rect_end(.UI)
        return
    }

    draw_rect(.UI, inner, background_2, background_2)
    inner = pad_rect(inner, 4)

    clip_rect_begin(.UI, inner)
    defer clip_rect_end(.UI)

    for &step, i in module.steps {
        background, text := background, code_comment
        if module.active && i == module.active_step {
            background = code_highlight
            text = text_color
        }
        id := get_id(uintptr(&step))
        interpolate_speed :f32 = 5
        background = interpolate_color_hsva(background, id, state.delta, reset, speed = interpolate_speed)
        text = interpolate_color_hsva(text, get_id(step), state.delta, reset, speed = interpolate_speed)
        line := eat_top_rect_ref(&inner, 50, 4)
        draw_rect(.UI, line, background, background)
        draw_text(.UI, step, line - { 0, 3, 0, 0 }, text, scale = .8)
    }
}