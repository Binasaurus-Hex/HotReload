package game

import rl "vendor:raylib"
import "core:mem"
import "core:odin/tokenizer"
import "core:fmt"
import sa "core:container/small_array"
import "core:math/linalg"

SlideShow :: struct {
    stage:              int,
    previous_stage:     int,
    stage_timer:    Timer,
    enter: bool,
    delta: f32,
    modules: [ModuleId]Module,
    loop: bool,

    pong: Pong,
}

ModuleId :: enum {
    LINE,
    EXE,
    DLL,
    FILE,
    FILE_COPY,
    STATE,
}

module_title := #partial [ModuleId]string {
    .EXE = "exe",
    .DLL = "dll",
    .FILE = "game.odin",
    .FILE_COPY = "copy",
    .STATE = "state",
}

ModuleFeature :: enum {
    File, NoHeader, Block, Line
}

Module :: struct {
    features:   bit_set[ModuleFeature],

    // temp
    name:       string,
    code:       string,
    steps:      []string,

    // stored
    active_step: int,
    active:     bool,
    visible:    bool,
    rect:       Rect,
    target_rect: Rect,
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
    color := interpolate_color_hsva(color, id, delta, reset, speed = 5)
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

        if rl.IsKeyPressed(.L) do slideshow.loop ~= true
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
    case 6..=15:

        title_r := eat_top_rect_ref(&content, 100, 10)
        slide_text(slideshow, "code", title_r, scale = 2)

        init_modules :: proc(slideshow: ^SlideShow){
            slideshow.modules = {}

            slideshow.modules[.FILE] = {
                features = {.File},
                visible = true
            }
            slideshow.modules[.FILE_COPY].features = {.File}

            slideshow.modules[.EXE] = {
                visible = true
            }

            slideshow.modules[.STATE].features = { .Block }

            slideshow.modules[.LINE].features = { .Line }
        }

        if slideshow.stage == 6 && slideshow.enter && slideshow.previous_stage == 5 {
            init_modules(slideshow)
        }

        game_file :=    &slideshow.modules[.FILE]
        exe :=          &slideshow.modules[.EXE]
        dll :=          &slideshow.modules[.DLL]
        file_copy :=    &slideshow.modules[.FILE_COPY]
        gamestate :=    &slideshow.modules[.STATE]
        line :=         &slideshow.modules[.LINE]

        game_file.features = { .File }
        file_copy.features = { .File }
        gamestate.features = { .Block }
        line.features = { .Line }

        // set dynamic initial state
        game_file.code = string(#load("game.odin"))
        file_copy.code = game_file.code

        exe.steps = { "build", "run" }
        dll.steps = { "check reload", "update", "render" }

        // layout
        middle := pad_rect(centre_rect(content), -{300, 200 })
        top_row := eat_top_rect_ref(&middle, 100, 200)
        bottom_row := eat_top_rect_ref(&middle, 200, 200)

        // start places
        game_file.target_rect = pad_rect(centre_rect(top_row), -{80, 100 })
        left, right := eat_left_rect(bottom_row, 200, 200)
        exe.target_rect = left
        dll.target_rect = right

        switch slideshow.stage {
        case 6:
            dll.visible = false
            gamestate.visible = false
            exe.visible = true
            exe.active = false
            file_copy.visible = false
            file_copy.rect = game_file.rect
            file_copy.active = false
        case 7:
            file_copy.visible = true
            file_copy.target_rect = game_file.rect - { 200, 0, 0, 0 }
            exe.active = true
            exe.active_step = 0
            file_copy.active = true
            file_copy.features -= {.NoHeader}
        case 8:
            file_copy.target_rect = exe.rect
            file_copy.features += {.NoHeader}
            file_copy.target_rect.zw = 50
            dll.visible = false
            dll.rect = file_copy.rect + { 150, 0, 10, 10 }
            exe.active_step = 0

        case 9:
            exe.active_step = -1
            dll.visible = true
            file_copy.visible = false
            dll.active = false
            line.target_rect.xy = exe.rect.xy + { 200, 100 }
            line.target_rect.zw = line.target_rect.xy
            line.rect = line.target_rect
            line.visible = false

            gamestate.visible = false

        case 10:
            exe.active_step = 1
            dll.active = true
            dll.active_step = -1
            line.visible = true
            line.target_rect.zw = dll.target_rect.xy + { 10, 0 }
            gamestate.rect.xy = line.target_rect.xy
        case 11:
            gamestate.visible = true
            gamestate.target_rect.zw = 40
            gamestate.target_rect.xy = line.target_rect.zw - { 20, 0 }
        case 12:
            gamestate.visible = false
            dll.active_step = int(state.elapsed) % len(dll.steps)
            game_file.active = dll.active_step == 0

            scale: f32 = .8
            color := rl.GetColor(CODE_COMMENT)
            text := "modified?"
            id := get_id(text)
            if game_file.active {
                scale = 1
                color = rl.GetColor(0xE67D74FF)
                text = "modified? False"
            }
            slide_text(slideshow, text, game_file.rect + { 200, 0, 0, 0 }, id = id, scale = scale, color = color, flags = {})

        case 13:
            dll.active_step = 0
            game_file.active = true


            color := rl.GetColor(0x82AAA3FF)
            id := get_id("modified?")
            slide_text(slideshow, "modified? True", game_file.rect + { 200, 0, 0, 0 }, id = id, scale = 1, color = color, flags = {})

        case 14:
            line.target_rect.zw = line.target_rect.xy + { 10, 0 }
            gamestate.visible = true
            gamestate.target_rect.xy = line.target_rect.xy
            dll.active = false
            dll.target_rect.xy += { 0, 1000 }
        case 15:
            if slideshow.loop do slideshow.stage = 6
            break
        }

        for id in ModuleId {
            slide_draw_module(slideshow, id)
        }
    case 16:

        top := eat_top_rect_ref(&content, 50, 10)
        slide_text(slideshow, "PONG!", top, scale = 2, reset = true)

        game_rect := pad_rect(centre_rect(content), { -409, -300 })
        run_pong(&slideshow.pong, game_rect, delta)
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

slide_draw_module :: proc(slideshow: ^SlideShow, module_id: ModuleId){

    module := &slideshow.modules[module_id]
    module.name = module_title[module_id]

    if !module.visible do return

    shadow_height: f32 = 10
    if .Line in module.features do shadow_height = 5
    shadow_begin(.UI, shadow_height)
    id := get_id(uintptr(module))

    module.rect = damp(module.rect, module.target_rect, f32(5), state.delta)
    rect := module.rect

    code_comment := rl.GetColor(CODE_COMMENT)
    background := rl.GetColor(BACKGROUND_5)
    raised := rl.ColorBrightness(background, -.1)
    background_2 := rl.GetColor(0x15212AFF)
    text_color := rl.GetColor(TEXT_COLOR)
    code_highlight := rl.GetColor(CODE_HIGHLIGHT)

    if .Line in module.features {
        line := transmute([2][2]f32)rect
        draw_line(.UI, line, code_highlight, 5, rounded = true)
        return
    }

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
        background = interpolate_color_hsva(background, id, state.delta, false, speed = interpolate_speed)
        text = interpolate_color_hsva(text, get_id(step), state.delta, false, speed = interpolate_speed)
        line := eat_top_rect_ref(&inner, 50, 4)
        draw_rect(.UI, line, background, background)
        draw_text(.UI, step, line - { 0, 3, 0, 0 }, text, scale = .8)
    }
}